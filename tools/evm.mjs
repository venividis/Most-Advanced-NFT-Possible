/*───────────────────────────────────────────────────────────────────────────
  A small harness around @ethereumjs/vm: deploy, call, read, and account for
  the gas. Enough to run the whole collection end to end in this process,
  with no node, no network and no fork.
───────────────────────────────────────────────────────────────────────────*/
import { createVM, runTx } from "@ethereumjs/vm";
import { Common, Mainnet, Hardfork } from "@ethereumjs/common";
import {
  Account, createAddressFromString, hexToBytes, bytesToHex, createAddressFromPrivateKey
} from "@ethereumjs/util";
import { createLegacyTx } from "@ethereumjs/tx";
import { createBlock } from "@ethereumjs/block";
import { keccak256 } from "ethereum-cryptography/keccak.js";

export const common = new Common({ chain: Mainnet, hardfork: Hardfork.Cancun });

/* A plausible mainnet block, so block.number, timestamp and prevrandao are
   the sort of values the contracts will actually see. */
export const BLOCK = createBlock(
  {
    header: {
      number: 21_000_000n,
      timestamp: 1_733_000_000n,
      gasLimit: 400_000_000n,
      baseFeePerGas: 7n,
      difficulty: 0n,
      mixHash: "0x" + "5e".repeat(32)
    }
  },
  { common, skipConsensusFormatValidation: true }
);

/*──────────────── tiny ABI coder (enough for the harness) ────────────────*/
const pad = (h) => h.replace(/^0x/, "").padStart(64, "0");

export function sel(sig) {
  return "0x" + Buffer.from(keccak256(Buffer.from(sig, "utf8"))).toString("hex").slice(0, 8);
}

export function enc(sig, args = []) {
  const m = sig.match(/^([\w$]+)\((.*)\)$/);
  const types = m[2].trim() ? m[2].split(",").map((s) => s.trim()) : [];
  let head = "", tail = "";
  const headLen = types.length * 32;
  const word = (t, v) => {
    if (t === "address") return pad(String(v).slice(2).toLowerCase());
    if (t === "bool") return pad(v ? "1" : "0");
    if (t === "bytes32") {
      // a number means the value, not the digits: 77 is 0x4d, not 0x77
      if (typeof v === "number" || typeof v === "bigint") return pad(BigInt(v).toString(16));
      return pad(String(v).replace(/^0x/, ""));
    }
    if (/^u?int/.test(t)) {
      let n = BigInt(v);
      if (n < 0n) n = (1n << 256n) + n;
      return pad(n.toString(16));
    }
    throw new Error("harness cannot encode " + t);
  };
  for (let i = 0; i < types.length; i++) {
    const t = types[i], v = args[i];
    if (t === "bytes" || t === "string") {
      const b = t === "string" ? Buffer.from(String(v), "utf8") : Buffer.from(String(v).replace(/^0x/, ""), "hex");
      head += pad((headLen + tail.length / 2).toString(16));
      tail += pad(b.length.toString(16)) + b.toString("hex").padEnd(Math.ceil(b.length / 32) * 64, "0");
    } else if (t === "bytes32[]") {
      const arr = v || [];
      head += pad((headLen + tail.length / 2).toString(16));
      tail += pad(arr.length.toString(16)) + arr.map((x) => pad(String(x).replace(/^0x/, ""))).join("");
    } else head += word(t, v);
  }
  return sel(sig) + head + tail;
}

export const decUint = (hex, i = 0) => BigInt("0x" + (hex.replace(/^0x/, "").substr(i * 64, 64) || "0"));
export const decAddr = (hex, i = 0) => "0x" + hex.replace(/^0x/, "").substr(i * 64, 64).slice(24);
export const decBool = (hex, i = 0) => decUint(hex, i) !== 0n;

export function decString(hex) {
  const h = hex.replace(/^0x/, "");
  if (h.length < 128) return "";
  const off = Number(BigInt("0x" + h.substr(0, 64))) * 2;
  const len = Number(BigInt("0x" + h.substr(off, 64)));
  return Buffer.from(h.substr(off + 64, len * 2), "hex").toString("utf8");
}

/// @param at index of the head word holding the offset to the array
export function decStringArray(hex, at = 0) {
  const h = hex.replace(/^0x/, "");
  const base = Number(BigInt("0x" + h.substr(at * 64, 64))) * 2;
  const n = Number(BigInt("0x" + h.substr(base, 64)));
  const out = [];
  for (let i = 0; i < n; i++) {
    const off = base + 64 + Number(BigInt("0x" + h.substr(base + 64 + i * 64, 64))) * 2;
    const len = Number(BigInt("0x" + h.substr(off, 64)));
    out.push(Buffer.from(h.substr(off + 64, len * 2), "hex").toString("utf8"));
  }
  return out;
}

/*──────────────── the chain ────────────────*/
export class Chain {
  constructor(vm, key) {
    this.vm = vm;
    this.key = key;
    this.from = createAddressFromPrivateKey(key);
    this.nonce = 0n;
    this.gas = {};
  }

  static async open() {
    const vm = await createVM({ common });
    const key = hexToBytes("0x" + "11".repeat(32));
    const chain = new Chain(vm, key);
    await vm.stateManager.putAccount(
      chain.from,
      new Account(0n, 10n ** 24n)
    );
    return chain;
  }

  async fund(addrHex, wei) {
    const a = createAddressFromString(addrHex);
    const acct = (await this.vm.stateManager.getAccount(a)) ?? new Account();
    acct.balance += BigInt(wei);
    await this.vm.stateManager.putAccount(a, acct);
  }

  async send({ to = null, data = "0x", value = 0n, label = "", gasLimit = 400_000_000n }) {
    // read the nonce back from state rather than tracking it: a tx that
    // reverts still consumes one, and a tx rejected at validation does not
    const sender = await this.vm.stateManager.getAccount(this.from);
    const tx = createLegacyTx(
      {
        nonce: sender ? sender.nonce : 0n,
        gasPrice: 10n,
        gasLimit,
        to: to ? createAddressFromString(to) : undefined,
        value: BigInt(value),
        data: hexToBytes(data.startsWith("0x") ? data : "0x" + data)
      },
      { common }
    ).sign(this.key);

    const res = await runTx(this.vm, {
      tx, block: BLOCK,
      skipBalance: true, skipBlockGasLimitValidation: true, skipHardForkValidation: true
    });
    const err = res.execResult.exceptionError;
    if (err) {
      const ret = bytesToHex(res.execResult.returnValue || new Uint8Array());
      throw new Error(
        `${label || "tx"} reverted: ${err.error}` + (ret && ret !== "0x" ? ` data=${ret.slice(0, 138)}` : "")
      );
    }
    if (label) this.gas[label] = (this.gas[label] || 0n) + res.totalGasSpent;
    return {
      gas: res.totalGasSpent,
      address: res.createdAddress ? res.createdAddress.toString() : null,
      ret: bytesToHex(res.execResult.returnValue || new Uint8Array()),
      logs: res.execResult.logs || []
    };
  }

  async deploy(bytecode, args = "", label = "") {
    const r = await this.send({ data: bytecode + args, label: label || "deploy" });
    if (!r.address) throw new Error("deployment produced no address");
    return r.address;
  }

  /// @dev A read. Runs as a call so state is untouched and gas is free.
  async call(to, data, from) {
    const res = await this.vm.evm.runCall({
      to: createAddressFromString(to),
      caller: createAddressFromString(from || this.from.toString()),
      origin: createAddressFromString(from || this.from.toString()),
      data: hexToBytes(data.startsWith("0x") ? data : "0x" + data),
      gasLimit: 3_000_000_000n,
      value: 0n,
      block: BLOCK
    });
    if (res.execResult.exceptionError) {
      const ret = bytesToHex(res.execResult.returnValue || new Uint8Array());
      throw new Error(`call reverted: ${res.execResult.exceptionError.error} ${ret.slice(0, 138)}`);
    }
    this.lastGas = res.execResult.executionGasUsed;
    return bytesToHex(res.execResult.returnValue);
  }

  async read(to, sig, args = []) {
    return this.call(to, enc(sig, args));
  }

  async exec(to, sig, args = [], opts = {}) {
    return this.send({ to, data: enc(sig, args), label: opts.label || sig, ...opts });
  }

  async codeSize(addrHex) {
    const code = await this.vm.stateManager.getCode(createAddressFromString(addrHex));
    return code.length;
  }
}

export function encodeAddressArg(a) {
  return pad(String(a).slice(2).toLowerCase());
}
export function encodeUintArg(n) {
  return pad(BigInt(n).toString(16));
}
