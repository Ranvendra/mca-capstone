#!/usr/bin/env python3
"""
gen_waveforms.py
Generates clean SVG timing diagrams representing the three primary verification scenarios:
  1. Cold miss and 4-word refill (22 cycles)
  2. Spatial locality hits (1 cycle per word)
  3. Conflict miss ping-pong between same-index lines
"""

import os

SVG_TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 {height}" width="100%" height="{height}" style="background-color: #1e1e2e; font-family: monospace;">
<style>
  .title {{ fill: #cdd6f4; font-size: 16px; font-weight: bold; }}
  .sig-name {{ fill: #89b4fa; font-size: 13px; font-weight: bold; }}
  .bus-text {{ fill: #11111b; font-size: 11px; font-weight: bold; text-anchor: middle; }}
  .wire-hi {{ stroke: #a6e3a1; stroke-width: 2.5; fill: none; }}
  .wire-lo {{ stroke: #6c7086; stroke-width: 2; fill: none; }}
  .wire-pulse {{ stroke: #f9e2af; stroke-width: 2.5; fill: none; }}
  .bus-poly {{ fill: #b4befe; stroke: #89b4fa; stroke-width: 1.5; }}
  .grid {{ stroke: #313244; stroke-width: 1; stroke-dasharray: 4,4; }}
  .cycle-num {{ fill: #6c7086; font-size: 10px; text-anchor: middle; }}
</style>
<text x="30" y="30" class="title">{title}</text>
{content}
</svg>
"""

def render_diagram(title, cycles, signals, out_path):
    left_margin = 140
    top_margin = 60
    row_height = 40
    cycle_width = max(24, int((960 - left_margin) / len(cycles)))
    total_height = top_margin + len(signals) * row_height + 40

    parts = []

    # Cycle header and grid
    for idx, c in enumerate(cycles):
        x = left_margin + idx * cycle_width
        parts.append(f'<text x="{x + cycle_width/2}" y="{top_margin - 12}" class="cycle-num">C{c}</text>')
        parts.append(f'<line x1="{x}" y1="{top_margin - 5}" x2="{x}" y2="{total_height - 30}" class="grid" />')
    x_end = left_margin + len(cycles) * cycle_width
    parts.append(f'<line x1="{x_end}" y1="{top_margin - 5}" x2="{x_end}" y2="{total_height - 30}" class="grid" />')

    # Draw signals
    for s_idx, (sig_name, sig_type, values) in enumerate(signals):
        y_base = top_margin + s_idx * row_height
        parts.append(f'<text x="25" y="{y_base + 20}" class="sig-name">{sig_name}</text>')

        if sig_type == 'clk':
            path_d = []
            for idx in range(len(cycles)):
                x = left_margin + idx * cycle_width
                hw = cycle_width / 2
                path_d.append(f"M {x} {y_base + 24} L {x} {y_base + 6} L {x + hw} {y_base + 6} L {x + hw} {y_base + 24} L {x + cycle_width} {y_base + 24}")
            parts.append(f'<path d="{" ".join(path_d)}" stroke="#cdd6f4" stroke-width="1.5" fill="none" />')

        elif sig_type == 'bit':
            path_d = []
            for idx, val in enumerate(values):
                x = left_margin + idx * cycle_width
                y = y_base + 6 if val else y_base + 24
                if idx == 0:
                    path_d.append(f"M {x} {y}")
                else:
                    prev_y = y_base + 6 if values[idx-1] else y_base + 24
                    if prev_y != y:
                        path_d.append(f"L {x} {y}")
                path_d.append(f"L {x + cycle_width} {y}")
            color_class = "wire-pulse" if ("hit" in sig_name or "miss" in sig_name or "ack" in sig_name or "ready" in sig_name) else "wire-hi"
            parts.append(f'<path d="{" ".join(path_d)}" class="{color_class}" />')

        elif sig_type == 'bus':
            # Run-length group consecutive equal bus values
            i = 0
            while i < len(values):
                val = values[i]
                start_i = i
                while i < len(values) and values[i] == val:
                    i += 1
                end_i = i
                x1 = left_margin + start_i * cycle_width
                x2 = left_margin + end_i * cycle_width
                if val is not None:
                    # Polygon for bus
                    poly = f'<polygon points="{x1+2},{y_base+15} {x1+6},{y_base+6} {x2-6},{y_base+6} {x2-2},{y_base+15} {x2-6},{y_base+24} {x1+6},{y_base+24}" class="bus-poly" />'
                    txt = f'<text x="{(x1+x2)/2}" y="{y_base+19}" class="bus-text">{val}</text>'
                    parts.append(poly + txt)
                else:
                    parts.append(f'<line x1="{x1}" y1="{y_base+15}" x2="{x2}" y2="{y_base+15}" stroke="#45475a" stroke-width="1.5" />')

    svg_content = SVG_TEMPLATE.format(
        title=title,
        height=total_height,
        content="\n".join(parts)
    )

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w") as f:
        f.write(svg_content)
    print(f"Generated: {out_path}")


def generate_all():
    docs_wf = os.path.join(os.path.dirname(__file__), "..", "docs", "waveforms")

    # 1. Cold Miss + Refill (Cycles 1 to 23)
    c1 = list(range(1, 24))
    s1 = [
        ("clk", "clk", [0]*23),
        ("cpu_valid", "bit", [1]*22 + [0]),
        ("cpu_addr", "bus", ["0x1000"]*22 + [None]),
        ("FSM state", "bus", ["IDLE"] + ["REFILL"]*20 + ["RESPOND", "IDLE"]),
        ("stat_miss", "bit", [1] + [0]*22),
        ("mem_req", "bit", [0] + [1]*20 + [0, 0]),
        ("mem_addr", "bus", [None] + ["0x1000"]*5 + ["0x1004"]*5 + ["0x1008"]*5 + ["0x100C"]*5 + [None, None]),
        ("mem_ack", "bit", [0]*5 + [1] + [0]*4 + [1] + [0]*4 + [1] + [0]*4 + [1, 0, 0]),
        ("cpu_ready", "bit", [0]*21 + [1, 0]),
        ("cpu_rdata", "bus", [None]*21 + ["D[0x1000]", None]),
    ]
    render_diagram("Waveform 1: Cold Miss and 4-Word Refill Sequence (22 Cycles)", c1, s1, os.path.join(docs_wf, "waveform_cold_miss.svg"))

    # 2. Spatial Hits in Same Block (Cycles 1 to 5)
    c2 = list(range(1, 6))
    s2 = [
        ("clk", "clk", [0]*5),
        ("cpu_valid", "bit", [1, 1, 1, 1, 0]),
        ("cpu_addr", "bus", ["0x1000", "0x1004", "0x1008", "0x100C", None]),
        ("FSM state", "bus", ["IDLE", "IDLE", "IDLE", "IDLE", "IDLE"]),
        ("stat_hit", "bit", [1, 1, 1, 1, 0]),
        ("cpu_ready", "bit", [1, 1, 1, 1, 0]),
        ("cpu_rdata", "bus", ["W0", "W1", "W2", "W3", None]),
        ("mem_req", "bit", [0, 0, 0, 0, 0]),
    ]
    render_diagram("Waveform 2: Spatial Locality Sequential Hits (1 Cycle Each)", c2, s2, os.path.join(docs_wf, "waveform_spatial_hits.svg"))

    # 3. Conflict Miss Ping-Pong (Addr A vs Addr B, same index)
    c3 = list(range(1, 13))
    s3 = [
        ("clk", "clk", [0]*12),
        ("cpu_valid", "bit", [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0]),
        ("cpu_addr", "bus", ["0x2010", "0x2010", None, "0x2410", "0x2410", None, "0x2010", "0x2010", None, "0x2410", "0x2410", None]),
        ("FSM state", "bus", ["IDLE", "REFILL", None, "IDLE", "REFILL", None, "IDLE", "REFILL", None, "IDLE", "REFILL", None]),
        ("stat_miss", "bit", [1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0]),
        ("stat_hit", "bit", [0]*12),
        ("cpu_ready", "bit", [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
    ]
    render_diagram("Waveform 3: Conflict Miss Ping-Pong (Index Collision Evictions)", c3, s3, os.path.join(docs_wf, "waveform_conflict_miss.svg"))


if __name__ == "__main__":
    generate_all()
