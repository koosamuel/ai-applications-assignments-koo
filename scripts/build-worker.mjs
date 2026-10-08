import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDir, "..");
const dist = resolve(root, "dist");
const serverDir = resolve(dist, "server");
await rm(dist, { recursive: true, force: true });
await mkdir(resolve(dist, ".openai"), { recursive: true });
await mkdir(serverDir, { recursive: true });

const [html, manifest, serviceWorker, worker, hosting] = await Promise.all([
  readFile(resolve(root, "index.html"), "utf8"),
  readFile(resolve(root, "manifest.webmanifest"), "utf8"),
  readFile(resolve(root, "sw.js"), "utf8"),
  readFile(resolve(root, "worker-src", "index.js"), "utf8"),
  readFile(resolve(root, ".openai", "hosting.json"), "utf8"),
]);

const assets = [
  "export const INDEX_HTML = " + JSON.stringify(html) + ";",
  "export const MANIFEST_JSON = " + JSON.stringify(manifest) + ";",
  "export const SERVICE_WORKER = " + JSON.stringify(serviceWorker) + ";",
  "",
].join("\n");

await Promise.all([
  writeFile(resolve(serverDir, "assets.js"), assets, "utf8"),
  writeFile(resolve(serverDir, "index.js"), worker, "utf8"),
  writeFile(resolve(dist, ".openai", "hosting.json"), hosting, "utf8"),
]);
console.log("Worker build ready:", dist);
