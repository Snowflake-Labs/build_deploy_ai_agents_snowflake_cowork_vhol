"""Render a campaign report HTML file from a JSON data file.

Usage: python render_report.py <data.json> [output_dir]
Prints the path of the saved HTML file.
"""
import html
import json
import os
import sys
from datetime import datetime

CSS = (
    "body{font-family:Arial,sans-serif;margin:20px;color:#222}"
    "h1{margin-bottom:0}h2{margin-top:4px;color:#444}"
    "table{border-collapse:collapse;width:100%;margin:20px 0}"
    "th{background-color:#4CAF50;color:white;padding:10px;text-align:left}"
    "td{padding:10px}tr:nth-child(even){background-color:#f2f2f2}"
    ".card{border:1px solid #ccc;padding:10px;margin:10px 0}"
    ".muted{color:#666}footer{text-align:center;color:#666}"
)


def esc(value):
    return html.escape("" if value is None else str(value))


def num(value, decimals=0):
    if value is None:
        return "N/A"
    return f"{float(value):,.{decimals}f}"


def money(value):
    return "N/A" if value is None else "$" + num(value, 2)


def pct(value):
    return "N/A" if value is None else num(value, 2) + "%"


def ratio_pct(numer, denom):
    if not numer or not denom:
        return None
    return float(numer) / float(denom) * 100


def render(data):
    c = data.get("campaign", {})
    m = data.get("metrics", {})
    fb = data.get("feedback") or {}
    parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Campaign Report</title>",
        f"<style>{CSS}</style></head><body>",
        "<h1>Campaign Report</h1>",
        f"<h2>{esc(c.get('name'))}</h2>",
        "<h3>Campaign Overview</h3><table><tr><th>Attribute</th><th>Value</th></tr>",
    ]
    overview = [
        ("Campaign ID", esc(c.get("id"))),
        ("Type", esc(c.get("type"))),
        ("Channel", esc(c.get("channel"))),
        ("Duration", f"{esc(c.get('start_date'))} to {esc(c.get('end_date'))}"),
        ("Budget", money(c.get("budget"))),
        ("Target Audience", esc(c.get("target_audience"))),
        ("Status", esc(c.get("status"))),
    ]
    parts += [f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in overview]
    parts.append("</table>")

    engagement = m.get("avg_engagement_rate")
    metrics = [
        ("Total Impressions", num(m.get("impressions"))),
        ("Total Clicks", num(m.get("clicks"))),
        ("Total Conversions", num(m.get("conversions"))),
        ("Click-Through Rate", pct(ratio_pct(m.get("clicks"), m.get("impressions")))),
        ("Conversion Rate", pct(ratio_pct(m.get("conversions"), m.get("clicks")))),
        ("Average Cost Per Click", money(m.get("avg_cpc"))),
        ("Average Cost Per Acquisition", money(m.get("avg_cpa"))),
        ("Total Revenue Generated", money(m.get("revenue"))),
        ("Average ROI", pct(m.get("avg_roi"))),
        ("Average Engagement Rate", pct(None if engagement is None else float(engagement) * 100)),
    ]
    parts.append("<h3>Performance Metrics</h3><table><tr><th>Metric</th><th>Value</th></tr>")
    parts += [f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in metrics]
    parts.append("</table>")

    parts.append("<h3>Customer Feedback Summary</h3>")
    entries = sorted(fb.get("entries") or [], key=lambda e: str(e.get("date") or ""), reverse=True)
    if entries or fb.get("count"):
        parts.append(f"<p><strong>Average Satisfaction Score:</strong> {num(fb.get('avg_score'), 2)} / 5.0</p>")
        parts.append(f"<p><strong>Number of Feedback Entries:</strong> {num(fb.get('count') or len(entries))}</p>")
        for e in entries:
            parts.append(
                "<div class='card'>"
                + (f"<p class='muted'>{esc(e.get('date'))}</p>" if e.get("date") else "")
                + f"<p><strong>Segment:</strong> {esc(e.get('segment'))}</p>"
                + f"<p><strong>Score:</strong> {num(e.get('score'), 2)} / 5.0</p>"
                + f"<p><strong>Comments:</strong> {esc(e.get('comments'))}</p>"
                + f"<p><strong>Recommendations:</strong> {esc(e.get('improvements'))}</p></div>"
            )
    else:
        parts.append("<p>No feedback available</p>")

    insights = data.get("insights") or []
    if insights:
        parts.append("<h3>Key Insights</h3><ul>")
        parts += [f"<li>{esc(i)}</li>" for i in insights]
        parts.append("</ul>")

    external = data.get("external_context") or []
    if external:
        parts.append("<h3>External Context</h3><ul>")
        for x in external:
            source = esc(x.get("source"))
            url = x.get("url") or ""
            # Only plain http(s) links are rendered as hyperlinks
            if url.startswith(("http://", "https://")):
                source = f"<a href='{esc(url)}'>{source or esc(url)}</a>"
            parts.append(f"<li>{esc(x.get('text'))} <span class='muted'>({source})</span></li>")
        parts.append("</ul>")

    generated = datetime.now().strftime("%Y-%m-%d %H:%M")
    parts.append(f"<hr><footer>Report Generated: {generated}</footer></body></html>")
    return "".join(parts)


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: python render_report.py <data.json> [output_dir]")
    with open(sys.argv[1]) as f:
        data = json.load(f)
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "campaign_reports"
    os.makedirs(out_dir, exist_ok=True)
    campaign_id = str(data.get("campaign", {}).get("id", "UNKNOWN"))
    safe_id = "".join(ch for ch in campaign_id if ch.isalnum() or ch in "-_") or "UNKNOWN"
    path = os.path.join(out_dir, f"CAMPAIGN_{safe_id}_{datetime.now().strftime('%Y-%m-%d_%H_%M')}.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(data))
    print(os.path.abspath(path))


if __name__ == "__main__":
    main()
