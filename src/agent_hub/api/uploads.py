"""Media fayllarni loyiha papkasiga yuklash: `POST /api/projects/{id}/uploads` (multipart)."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, File, Form, UploadFile

from agent_hub.services import uploads

from .deps import HubDep

router = APIRouter()


@router.post("/api/projects/{project_id}/uploads", status_code=201)
async def upload_files(
    hub: HubDep,
    project_id: str,
    files: Annotated[list[UploadFile], File()],
    cwd: Annotated[str | None, Form(max_length=1024)] = None,
    task_id: Annotated[str | None, Form(max_length=40)] = None,
) -> dict[str, Any]:
    project = hub.project(project_id)
    uploads.check_count(len(files))
    for upload in files:
        uploads.check_name(upload.filename or "")
    base = uploads.project_dir(project, cwd)
    directory = uploads.uploads_dir(project, cwd, task_id)

    stored: list[uploads.StoredFile] = []
    for upload in files:
        parts = await uploads.read_upload(upload.read, upload.filename or "")
        stored.append(uploads.store(directory, base, upload.filename or "", parts))
    return {"files": [item.as_dict() for item in stored]}
