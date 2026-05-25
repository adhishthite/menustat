"use client";

import { useEffect, useState } from "react";

type Channel = {
  key: string;
  label: string;
  unit: string;
  /** index into the accent color set */
  tone: "cpu" | "mem" | "gpu" | "pres" | "fan";
  base: number;
  spread: number;
  /** how many of the 14 segments map to 100% */
  max: number;
};

const CHANNELS: Channel[] = [
  { key: "cpu", label: "CPU", unit: "%", tone: "cpu", base: 24, spread: 18, max: 100 },
  { key: "mem", label: "MEM", unit: "%", tone: "mem", base: 57, spread: 9, max: 100 },
  { key: "gpu", label: "GPU", unit: "%", tone: "gpu", base: 30, spread: 22, max: 100 },
  { key: "pres", label: "PRES", unit: "", tone: "pres", base: 18, spread: 10, max: 100 },
  { key: "fan", label: "FAN", unit: "%", tone: "fan", base: 12, spread: 14, max: 100 }
];

const SEGMENTS = 14;

function drift(base: number, spread: number) {
  // Bounded random walk so the numbers feel alive but plausible.
  const v = base + (Math.random() - 0.5) * 2 * spread;
  return Math.max(2, Math.min(99, Math.round(v)));
}

function pressureLabel(v: number) {
  if (v < 33) return "NORMAL";
  if (v < 66) return "MODERATE";
  return "HIGH";
}

export default function LiveTelemetry() {
  const [values, setValues] = useState<Record<string, number>>(() =>
    Object.fromEntries(CHANNELS.map((c) => [c.key, c.base]))
  );

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return;

    const tick = () =>
      setValues((prev) => {
        const next: Record<string, number> = {};
        for (const c of CHANNELS) {
          // Ease toward a fresh target for smoother motion than pure random.
          const target = drift(c.base, c.spread);
          next[c.key] = Math.round(prev[c.key] + (target - prev[c.key]) * 0.55);
        }
        return next;
      });

    const id = window.setInterval(tick, 1400);
    return () => window.clearInterval(id);
  }, []);

  return (
    <div className="telemetry" role="img" aria-label="Live system metrics simulation">
      {CHANNELS.map((c) => {
        const v = values[c.key];
        const filled = Math.round((v / c.max) * SEGMENTS);
        const readout = c.key === "pres" ? pressureLabel(v) : `${v}${c.unit}`;
        return (
          <div className="tChan" data-tone={c.tone} key={c.key}>
            <div className="tHead">
              <span className="tLabel">{c.label}</span>
              <span className="tValue">{readout}</span>
            </div>
            <div className="tBar" aria-hidden="true">
              {Array.from({ length: SEGMENTS }).map((_, i) => (
                <span key={i} data-on={i < filled ? "1" : "0"} />
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}
