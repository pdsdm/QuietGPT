import csv
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


def export_table(trace, schemas, target):
    for schema in schemas:
        xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
        with open(target, "w") as out:
            result = subprocess.run(
                ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
                stdout=out,
                stderr=subprocess.DEVNULL,
            )
        if result.returncode == 0:
            return
    sys.exit(f"The trace has none of these tables: {schemas}")


def rows(path):
    root = ET.parse(path).getroot()
    columns = [c.findtext("mnemonic") for c in root.iter("col")]
    seen = {}

    def resolve(element):
        ref = element.get("ref")
        if ref:
            return seen[ref]
        if element.get("id"):
            seen[element.get("id")] = element
        for child in element:
            resolve(child)
        return element

    for row in root.iter("row"):
        values = [resolve(cell) for cell in row]
        yield dict(zip(columns, values))


def add_busy(buckets, start, duration):
    end = start + duration
    while start < end:
        second = int(start)
        stop = min(end, second + 1)
        buckets[second] += stop - start
        start = stop


def merged(intervals):
    total = []
    for start, duration in sorted(intervals):
        end = start + duration
        if total and start <= total[-1][1]:
            total[-1][1] = max(total[-1][1], end)
        else:
            total.append([start, end])
    return [(start, end - start) for start, end in total]


def main():
    trace, output = sys.argv[1], Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    ane_xml, gpu_xml = output / "ane.xml", output / "gpu.xml"
    export_table(trace, ["ane-hw-intervals-internal", "ane-hw-intervals"], ane_xml)
    export_table(trace, ["metal-gpu-intervals"], gpu_xml)

    ane = []
    labels = defaultdict(int)
    for row in rows(ane_xml):
        ane.append((int(row["start"].text) / 1e9, int(row["duration"].text) / 1e9))
        labels[row["event-label"].get("fmt", "").strip()] += 1

    ane_busy = defaultdict(float)
    for start, duration in merged(ane):
        add_busy(ane_busy, start, duration)

    by_process = defaultdict(list)
    for row in rows(gpu_xml):
        process = row.get("process")
        name = process.get("fmt", "").split(" (")[0] if process is not None else ""
        by_process[name or "unknown"].append(
            (int(row["start"].text) / 1e9, int(row["duration"].text) / 1e9)
        )

    gpu_busy = {}
    for name, intervals in by_process.items():
        buckets = defaultdict(float)
        for start, duration in merged(intervals):
            add_busy(buckets, start, duration)
        gpu_busy[name] = buckets

    names = sorted(gpu_busy, key=lambda n: -sum(gpu_busy[n].values()))
    last = max(list(ane_busy) + [s for b in gpu_busy.values() for s in b] + [0])
    with open(output / "per-second.csv", "w", newline="") as out:
        writer = csv.writer(out)
        writer.writerow(["second", "ane_busy_percent"] + [f"gpu_ms_{n}" for n in names])
        for second in range(last + 1):
            writer.writerow(
                [second, round(ane_busy[second] * 100, 1)]
                + [round(gpu_busy[n][second] * 1000, 1) for n in names]
            )

    ane_xml.unlink()
    gpu_xml.unlink()
    print("Neural Engine events:", dict(labels))
    print("Neural Engine busy total: %.2f s" % sum(ane_busy.values()))
    for name in names:
        print("GPU %s: %.2f s" % (name, sum(gpu_busy[name].values())))
    print("Per-second table:", output / "per-second.csv")


main()
