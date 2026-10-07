export const NATIVE_PASTE_EVENT = "agent-hub-native-paste-files";

export interface NativePasteFile {
  name: string;
  type?: string;
  dataBase64: string;
}

function isNativePasteFile(value: unknown): value is NativePasteFile {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.name === "string" &&
    item.name.trim() !== "" &&
    typeof item.dataBase64 === "string" &&
    item.dataBase64 !== "" &&
    (item.type === undefined || typeof item.type === "string")
  );
}

function bytesFromBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function nativePasteFiles(detail: unknown): File[] {
  if (typeof detail !== "object" || detail === null) return [];
  const files = (detail as Record<string, unknown>).files;
  if (!Array.isArray(files)) return [];
  return files.flatMap((item) => {
    if (!isNativePasteFile(item)) return [];
    try {
      const bytes = bytesFromBase64(item.dataBase64);
      const buffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(buffer).set(bytes);
      return [
        new File([buffer], item.name.trim(), {
          type: item.type ?? "application/octet-stream",
        }),
      ];
    } catch {
      return [];
    }
  });
}
