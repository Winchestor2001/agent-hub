"""Push yangilanishlar: KanBot `/ws/web` hodisalari → brauzerga SSE (`GET /api/events`).

Brauzerga ma'lumotning o'zi emas, faqat "qaysi so'rov eskirdi" signali (mavzu) boradi: UI tegishli
REST so'rovni qayta bajaradi. Shunda holat (`effective_state`, vazifaga bog'lash) bitta joyda
hisoblanadi, polling esa hodisa yo'qolsa ham zaxira bo'lib qoladi.

KanBot hub'i hodisalarni har obunachiga ketma-ket `await send` bilan yuboradi, shuning uchun
upstream doim o'qiladi. Obunachida navbat yo'q — faqat kutilayotgan mavzular to'plami: sekin brauzer
xotirani ham, KanBot oqimini ham to'xtatmaydi. Upstream bitta va faqat obunachi bor paytda ochiq.

SSE: `event: ready` (ulanish ochildi — UI hammasini yangilaydi), `event: invalidate` +
`data: {"topics": [...]}`, har `HEARTBEAT` s da `: ping` (yopilgan ulanishni aniqlash uchun).
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
from collections.abc import AsyncGenerator, AsyncIterator, Awaitable, Callable, Iterable
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from .terminal import UPSTREAM_CONNECT_ERRORS, Channel, open_upstream, quietly

logger = logging.getLogger(__name__)

router = APIRouter()

Topic = Literal["sessions", "health"]
ALL_TOPICS: frozenset[Topic] = frozenset(("sessions", "health"))

# `agent.sessions.updated` va `card.*`/`build.*` UI uchun kerak emas (o'tgan sessiyalar pane
# o'zgarishi bilan birga yangilanadi).
EVENT_TOPICS: dict[str, frozenset[Topic]] = {
    "pane.updated": frozenset(("sessions",)),
    "panes.updated": frozenset(("sessions",)),
    "agent.blocked": frozenset(("sessions",)),
    "runner.updated": frozenset(("health",)),
}

COALESCE = 0.05
HEARTBEAT = 15.0
RECONNECT_DELAYS = (0.5, 1.0, 2.0, 5.0)
RETRY_MS = 2000

Connect = Callable[[], Awaitable[Channel]]


def topics_for(raw: str) -> frozenset[Topic]:
    try:
        msg = json.loads(raw)
    except json.JSONDecodeError:
        return frozenset()
    if not isinstance(msg, dict):
        return frozenset()
    kind = msg.get("type")
    return EVENT_TOPICS.get(kind, frozenset()) if isinstance(kind, str) else frozenset()


class Subscription:
    def __init__(self, coalesce: float) -> None:
        self._coalesce = coalesce
        self._pending: set[Topic] = set()
        self._ready = asyncio.Event()

    def mark(self, topics: Iterable[Topic]) -> None:
        self._pending.update(topics)
        if self._pending:
            self._ready.set()

    async def next(self) -> frozenset[Topic]:
        """Kamida bitta mavzu paydo bo'lguncha kutadi; qisqa tanaffus ichidagilar birlashtiriladi.

        Bekor qilinsa (heartbeat timeout) kutilayotgan mavzular yo'qolmaydi.
        """
        await self._ready.wait()
        await asyncio.sleep(self._coalesce)
        topics = frozenset(self._pending)
        self._pending.clear()
        self._ready.clear()
        return topics


class EventHub:
    """KanBot hodisalarining obunachilarga tarqatuvchisi (bitta upstream ulanish)."""

    def __init__(
        self,
        connect: Connect,
        *,
        coalesce: float = COALESCE,
        reconnect_delays: tuple[float, ...] = RECONNECT_DELAYS,
    ) -> None:
        self._connect = connect
        self._coalesce = coalesce
        self._delays = reconnect_delays
        self._subs: set[Subscription] = set()
        self._task: asyncio.Task[None] | None = None
        self.connected = False

    @classmethod
    def for_url(cls, url: str) -> EventHub:
        return cls(lambda: open_upstream(url))

    @property
    def subscribers(self) -> int:
        return len(self._subs)

    @contextlib.asynccontextmanager
    async def subscribe(self) -> AsyncIterator[Subscription]:
        sub = Subscription(self._coalesce)
        self._subs.add(sub)
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._run_logged())
        try:
            yield sub
        finally:
            self._subs.discard(sub)
            if not self._subs:
                await self.close()

    async def close(self) -> None:
        task, self._task = self._task, None
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    def _mark(self, topics: Iterable[Topic]) -> None:
        topics = frozenset(topics)
        for sub in self._subs:
            sub.mark(topics)

    async def _run_logged(self) -> None:
        try:
            await self._run()
        except Exception:
            # Keyingi obunachi upstream'ni qayta ishga tushiradi; polling bu orada ishlaydi.
            logger.exception("hodisalar: upstream sikli to'xtadi")

    async def _run(self) -> None:
        failures = 0
        while self._subs:
            try:
                upstream = await self._connect()
            except UPSTREAM_CONNECT_ERRORS as exc:
                # KanBot o'chiq bo'lsa log har urinishda to'lmasin: faqat birinchi xato.
                if failures == 0:
                    logger.warning("hodisalar: KanBot /ws/web ga ulanib bo'lmadi: %s", exc)
                await asyncio.sleep(self._delays[min(failures, len(self._delays) - 1)])
                failures += 1
                continue
            self.connected = True
            if failures:
                logger.info("hodisalar: KanBot /ws/web ga qayta ulandi")
                # Uzilish paytida o'tkazib yuborilgan hodisalar o'rniga — hammasi yangilansin.
                self._mark(ALL_TOPICS)
            failures = 0
            try:
                while (raw := await upstream.recv()) is not None:
                    if topics := topics_for(raw):
                        self._mark(topics)
            finally:
                self.connected = False
                await quietly(upstream.close(1000, ""))
            logger.warning("hodisalar: KanBot /ws/web ulanishi uzildi")
            self._mark(ALL_TOPICS)
            await asyncio.sleep(self._delays[0])
            failures = 1


def _sse(event: str, data: object) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


async def event_stream(hub: EventHub, heartbeat: float = HEARTBEAT) -> AsyncGenerator[str]:
    """Cheksiz oqim; mijoz ketganini Starlette (yoki heartbeat yuborish xatosi) bekor qiladi."""
    async with hub.subscribe() as sub:
        yield f"retry: {RETRY_MS}\n" + _sse("ready", {})
        while True:
            try:
                async with asyncio.timeout(heartbeat):
                    topics = await sub.next()
            except TimeoutError:
                yield ": ping\n\n"
                continue
            yield _sse("invalidate", {"topics": sorted(topics)})


@router.get("/api/events")
async def events(request: Request) -> StreamingResponse:
    hub: EventHub = request.app.state.events
    return StreamingResponse(
        event_stream(hub),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
