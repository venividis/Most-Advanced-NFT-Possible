import { compile, artifact } from "./compile.mjs";
import { Chain, enc } from "./evm.mjs";
const out = compile({ quiet: true, dirs: ["src", "probe"] });
const A = artifact(out, "probe/AuditB64.sol", "AuditB64");
const chain = await Chain.open();
const c = await chain.deploy(A.bytecode, "", "AuditB64");
const rows = [];
for (const N of [8192, 24576, 40960, 55875, 73728, 90112, 110000, 131072, 155648]) {
  const hex = "0x" + "61".repeat(N);
  const o = await chain.call(c.address, enc("once(bytes)", [hex]));
  const t = await chain.call(c.address, enc("twice(bytes)", [hex]));
  rows.push({ N, once: Number(o.gas), twice: Number(t.gas) });
  console.log(`N=${String(N).padStart(7)}  once=${String(Number(o.gas)).padStart(10)}  twice=${String(Number(t.gas)).padStart(11)}`);
}
console.log("\n  marginal gas per DOCUMENT byte on the double-base64 path");
console.log("  (calldata cost is included and constant per byte, so subtract 16/byte for a storage-fed path)");
for (let i = 1; i < rows.length; i++) {
  const dN = rows[i].N - rows[i - 1].N, dG = rows[i].twice - rows[i - 1].twice;
  console.log(`  ${String(rows[i-1].N).padStart(7)} -> ${String(rows[i].N).padStart(7)}:  ${(dG/dN).toFixed(1)}  (minus calldata 16 => ${(dG/dN-16).toFixed(1)})`);
}
