import { ArrowUpRight, Cpu, Download, Gauge, Github } from "lucide-react";
import LiveTelemetry from "./LiveTelemetry";
import ThemeToggle from "./ThemeToggle";

const downloadUrl =
  "https://github.com/adhishthite/menustat/releases/latest/download/MenuStat.dmg";
const repoUrl = "https://github.com/adhishthite/menustat";
const version = "0.4.0";

// Spread onto any anchor pointing off-site so it opens in a new tab safely.
const ext = { target: "_blank", rel: "noopener noreferrer" } as const;

const signals = [
  {
    tag: "CPU",
    tone: "cpu",
    title: "Performance and efficiency cores",
    body: "System CPU split into user, system, idle, and per-core activity, with P/E labels so you can see where macOS is scheduling work."
  },
  {
    tag: "MEM",
    tone: "mem",
    title: "Unified memory, unpacked",
    body: "Used, active, wired, and compressed pages broken out — and a live ranking of what is holding the most RAM."
  },
  {
    tag: "GPU",
    tone: "gpu",
    title: "Apple GPU utilization",
    body: "Live device activity read from the AGX accelerator so you can see the graphics cost of what you are running."
  },
  {
    tag: "PRES",
    tone: "pres",
    title: "Plain-English pressure",
    body: "Normal, moderate, or high — with hover definitions and a heat-proxy list of likely culprits when memory starts to strain."
  },
  {
    tag: "FAN",
    tone: "fan",
    title: "Fan RPM, off the SMC",
    body: "Per-fan RPM read straight from AppleSMC, normalized to a range with a quiet / cooling / high status bucket."
  }
];

const specs = [
  ["Chip", "Apple Silicon · M1 and later"],
  ["macOS", "13 Ventura or later"],
  ["Footprint", "Menu-bar resident · no dock icon"],
  ["Cadence", "Selectable · 1s / 5s / 30s"],
  ["Signing", "Developer ID · notarized"],
  ["License", "Open source · MIT"]
];

export default function Home() {
  return (
    <main>
      <div className="grid-overlay" aria-hidden="true" />

      <header className="header shell">
        <a className="brand" href="#top" aria-label="MenuStat home">
          <span className="brandMark">MS</span>
          <span className="brandName">MENUSTAT</span>
        </a>
        <nav aria-label="Primary">
          <a href="#metrics">Metrics</a>
          <a href="#how">How it works</a>
          <a href={repoUrl} {...ext}>
            <Github size={16} />
            <span>Source</span>
          </a>
          <a className="navCta" href={downloadUrl} {...ext}>
            Apple Silicon
          </a>
          <ThemeToggle />
        </nav>
      </header>

      <section className="hero shell" id="top">
        <div className="heroCopy">
          <span className="eyebrow">
            <span className="pulse" aria-hidden="true" />
            Apple Silicon telemetry for developers
          </span>
          <h1>
            Watch your
            <br />
            Mac think.
          </h1>
          <p>
            CPU, unified memory, GPU, pressure, and fans — read straight off the
            silicon and drawn in one roomier menu-bar panel. Pick a refresh
            cadence, inspect P/E core activity, and hover any metric for a
            plain-English definition.
          </p>

          <LiveTelemetry />

          <div className="actions">
            <a className="button primary" href={downloadUrl} {...ext}>
              <Download size={18} />
              Download for Apple Silicon
            </a>
            <a className="button ghost" href={repoUrl} {...ext}>
              <Github size={18} />
              View source
            </a>
          </div>
          <p className="microline">
            Free · Apple Silicon required · macOS 13+ · v{version}{" "}· Signed
            &amp; notarized
          </p>
        </div>

        <div className="product" aria-label="MenuStat panel preview">
          <div className="productGlow" aria-hidden="true" />
          <div className="panelFrame">
            <img
              src="/menustat-panel.png"
              alt="MenuStat 0.4.0 showing refresh controls, P/E core CPU activity, hover help, and top app rows"
            />
          </div>
          <div className="floatChip chipA" aria-hidden="true">
            <span className="chipDot" />
            1s / 5s / 30s
          </div>
          <div className="floatChip chipB" aria-hidden="true">
            <span className="chipDot" />
            P/E cores
          </div>
        </div>
      </section>

      <section className="metrics shell" id="metrics" aria-label="What MenuStat reads">
        <div className="sectionHead">
          <span className="kicker">// Signals</span>
          <h2>Five readouts. One glance.</h2>
          <p>
            The whole machine, color-coded the way the app shows it. Choose the
            sections you care about, then open any metric for the full breakdown
            underneath.
          </p>
        </div>
        <div className="metricGrid">
          {signals.map((s) => (
            <article className="metricCard" data-tone={s.tone} key={s.tag}>
              <div className="metricTop">
                <span className="metricTag">{s.tag}</span>
                <div className="metricTrack" aria-hidden="true">
                  {Array.from({ length: 8 }).map((_, i) => (
                    <span key={i} />
                  ))}
                </div>
              </div>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="how shell" id="how" aria-label="How it works">
        <div className="howCard">
          <Cpu size={22} aria-hidden="true" />
          <h3>Read from the metal</h3>
          <p>
            Numbers come from Mach, <code>libproc</code>, and IOKit — not a
            polling shell-out. The UI only ever sees immutable snapshots, so
            what you read is exactly what the kernel reported.
          </p>
        </div>
        <div className="howCard">
          <Gauge size={22} aria-hidden="true" />
          <h3>Quiet by design</h3>
          <p>
            MenuStat runs as an <code>LSUIElement</code> — no dock icon, no
            window, nothing to manage. Sampling runs on a serial queue and skips
            overlapping ticks so it stays light.
          </p>
        </div>
        <div className="howCard">
          <span className="howPulse" aria-hidden="true" />
          <h3>Always current</h3>
          <p>
            Pick a 1s cadence while debugging, 5s for balanced monitoring, or
            30s for quiet residency. Heavier per-app sampling only runs while
            the panel is open.
          </p>
        </div>
      </section>

      <section className="specs shell" aria-label="Specifications">
        {specs.map(([k, v]) => (
          <div className="specRow" key={k}>
            <span className="specKey">{k}</span>
            <span className="specVal">{v}</span>
          </div>
        ))}
      </section>

      <section className="closing shell" id="download">
        <div className="closingInner">
          <span className="kicker">// Ready when you are</span>
          <h2>Put your Mac&apos;s pulse in the menu bar.</h2>
          <p>
            One small download. It lives quietly up top and tells you exactly
            what your Apple Silicon Mac is doing, the moment you ask.
          </p>
          <div className="actions center">
            <a className="button primary" href={downloadUrl} {...ext}>
              <Download size={18} />
              Download for Apple Silicon
            </a>
            <a className="button ghost" href={repoUrl} {...ext}>
              Read the source
              <ArrowUpRight size={18} />
            </a>
          </div>
          <p className="microline">
            v{version}{" "}· Apple Silicon required · Intel Macs show an unsupported
            alert · macOS 13+ · Developer ID signed &amp; notarized
          </p>
        </div>
      </section>

      <footer className="footer shell">
        <div className="brand">
          <span className="brandMark small">MS</span>
          <span className="brandName">MENUSTAT</span>
        </div>
        <div className="footerLinks">
          <a href={repoUrl} {...ext}>
            GitHub
          </a>
          <a href={`${repoUrl}/releases`} {...ext}>
            Releases
          </a>
          <a href={`${repoUrl}/blob/main/LICENSE`} {...ext}>
            MIT License
          </a>
        </div>
        <span className="footerNote">
          © {new Date().getFullYear()} Adhish Thite
        </span>
      </footer>
    </main>
  );
}
