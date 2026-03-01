// LSP FFI – Node.js stdin/stdout JSON-RPC transport
// This file is compiled alongside server.gleam and provides the I/O layer.

import { readSync } from "node:fs";
import { Result$Ok, Result$Error } from "../gleam.mjs";

// ---- Low-level stdin helpers ------------------------------------------------

/** Read exactly `n` bytes from stdin (fd 0) synchronously. Returns null on EOF. */
function readBytes(n) {
  const buf = Buffer.alloc(n);
  let offset = 0;
  while (offset < n) {
    const read = readSync(0, buf, offset, n - offset, null);
    if (read === 0) return null; // EOF
    offset += read;
  }
  return buf;
}

/** Read one line (terminated by \n) from stdin. Returns null on EOF. */
function readLine() {
  const chunks = [];
  const byte = Buffer.alloc(1);
  while (true) {
    const n = readSync(0, byte, 0, 1, null);
    if (n === 0) return null; // EOF
    if (byte[0] === 0x0a /* \n */) {
      return Buffer.concat(chunks).toString("utf8").replace(/\r$/, "");
    }
    chunks.push(Buffer.from([byte[0]]));
  }
}

// ---- Public API (called from Gleam via @external) ---------------------------

/**
 * Read one complete JSON-RPC message from stdin.
 * Returns Ok(parsed_object) or Error(undefined).
 */
export function readRequest() {
  try {
    let contentLength = -1;

    // Read headers until blank line
    while (true) {
      const line = readLine();
      if (line === null) return new Result$Error(undefined); // EOF
      if (line === "") break;
      const m = line.match(/^Content-Length:\s*(\d+)/i);
      if (m) contentLength = parseInt(m[1], 10);
    }

    if (contentLength < 0) return new Result$Error(undefined);

    const body = readBytes(contentLength);
    if (body === null) return new Result$Error(undefined);

    const obj = JSON.parse(body.toString("utf8"));
    return new Result$Ok(obj);
  } catch (_) {
    return new Result$Error(undefined);
  }
}

/**
 * Write a JSON-RPC message to stdout with LSP Content-Length framing.
 */
export function sendResponse(json) {
  const encoded = Buffer.from(json, "utf8");
  const header = `Content-Length: ${encoded.byteLength}\r\n\r\n`;
  process.stdout.write(header);
  process.stdout.write(encoded);
}

/**
 * Same as sendResponse – LSP notifications use the same framing.
 */
export function sendNotification(json) {
  sendResponse(json);
}

// ---- Dynamic field accessors ------------------------------------------------

/** Get a String field from a dynamic object. */
export function getStr(obj, key) {
  if (obj != null && typeof obj[key] === "string") {
    return new Result$Ok(obj[key]);
  }
  return new Result$Error(undefined);
}

/** Get an Int (number) field from a dynamic object. */
export function getInt(obj, key) {
  if (obj != null && typeof obj[key] === "number") {
    return new Result$Ok(obj[key]);
  }
  return new Result$Error(undefined);
}

/** Get a nested object field from a dynamic object. */
export function getNested(obj, key) {
  if (obj != null && obj[key] != null && typeof obj[key] === "object") {
    return new Result$Ok(obj[key]);
  }
  return new Result$Error(undefined);
}

/** Check whether a dynamic value is not null/undefined. */
export function isDefined(obj) {
  return obj != null;
}
