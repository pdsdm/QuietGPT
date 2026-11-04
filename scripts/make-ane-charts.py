import csv
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

THEMES = {
    "light": {
        "surface": "#fcfcfb",
        "text": "#0b0b0b",
        "muted": "#52514e",
        "grid": "#e4e3df",
        "band": "#efeeea",
        "ane": "#2a78d6",
        "cpu": "#eb6834",
        "gpu": "#1baf7a",
    },
    "dark": {
        "surface": "#1a1a19",
        "text": "#f0efec",
        "muted": "#c3c2b7",
        "grid": "#33332f",
        "band": "#2a2a27",
        "ane": "#3987e5",
        "cpu": "#d95926",
        "gpu": "#199e70",
    },
}


def load(path):
    with open(path) as source:
        return [{k: float(v) for k, v in row.items()} for row in csv.DictReader(source)]


def style(axis, theme):
    axis.set_facecolor(theme["surface"])
    for side in ("top", "right", "left"):
        axis.spines[side].set_visible(False)
    axis.spines["bottom"].set_color(theme["grid"])
    axis.tick_params(colors=theme["muted"], labelsize=9, length=0)
    axis.grid(axis="y", color=theme["grid"], linewidth=0.8)
    axis.set_axisbelow(True)


def power_chart(data, output, mode, theme):
    apple = load(data / "mac-apple-power.csv")
    gpu = [row for row in load(data / "mac-gpu-baseline-power.csv") if row["seconds"] <= 30]
    figure, axes = plt.subplots(1, 2, figsize=(9, 3.5), sharey=True, facecolor=theme["surface"])
    left, right = axes
    time = [row["seconds"] for row in apple]
    left.plot(time, [row["ane_w"] for row in apple], color=theme["ane"], linewidth=2, label="Neural Engine")
    left.plot(time, [row["cpu_w"] for row in apple], color=theme["cpu"], linewidth=2, label="CPU")
    left.plot(time, [row["gpu_w"] for row in apple], color=theme["gpu"], linewidth=2, label="GPU")
    right.plot([row["seconds"] for row in gpu], [row["gpu_w"] for row in gpu], color=theme["gpu"], linewidth=2)
    left.set_title("Apple Foundation Models: 2 replies", color=theme["text"], fontsize=11, loc="left")
    right.set_title("llama3.2:3b with Ollama: 3 replies", color=theme["text"], fontsize=11, loc="left")
    left.set_ylabel("Watts", color=theme["muted"], fontsize=9)
    left.text(15, 4.1, "Neural Engine 3.4 W", color=theme["text"], fontsize=9)
    right.text(8, 20.6, "GPU 19.1 W (CPU not read)", color=theme["text"], fontsize=9)
    left.legend(frameon=False, labelcolor=theme["muted"], fontsize=9, loc="upper left", ncols=3)
    for axis in axes:
        style(axis, theme)
        axis.set_xlim(0, 30)
        axis.set_ylim(0, 23)
        axis.set_xlabel("Seconds", color=theme["muted"], fontsize=9)
    figure.tight_layout()
    figure.savefig(output / f"mac-power-{mode}.png", facecolor=theme["surface"])
    plt.close(figure)


def iphone_chart(data, output, mode, theme):
    rows = load(data / "iphone-long-reply.csv")
    figure, axis = plt.subplots(figsize=(9, 3), facecolor=theme["surface"])
    axis.axvspan(11.5, 28.5, color=theme["band"], linewidth=0)
    axis.bar(
        [row["second"] for row in rows],
        [row["ane_busy_percent"] for row in rows],
        color=theme["ane"],
        width=0.75,
    )
    axis.text(12, 103, "Reply streams on the screen", color=theme["text"], fontsize=9)
    axis.set_title("iPhone 16 Pro Max: Neural Engine busy time in one reply", color=theme["text"], fontsize=11, loc="left", pad=16)
    axis.set_xlabel("Seconds of the recording", color=theme["muted"], fontsize=9)
    axis.set_ylabel("Busy, percent", color=theme["muted"], fontsize=9)
    axis.set_xlim(-0.8, 40.8)
    axis.set_ylim(0, 112)
    axis.set_yticks([0, 25, 50, 75, 100])
    style(axis, theme)
    figure.tight_layout()
    figure.savefig(output / f"iphone-busy-{mode}.png", facecolor=theme["surface"])
    plt.close(figure)


def main():
    root = Path(sys.argv[1])
    plt.rcParams["font.family"] = ["Helvetica", "Arial", "DejaVu Sans"]
    plt.rcParams["savefig.dpi"] = 200
    charts = root / "charts"
    charts.mkdir(exist_ok=True)
    for mode, theme in THEMES.items():
        power_chart(root / "data", charts, mode, theme)
        iphone_chart(root / "data", charts, mode, theme)


main()
