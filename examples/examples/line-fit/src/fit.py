"""Fit a straight line to points, as JSON: python3 fit.py METHOD POINTS OUTPUT.

METHOD is `ols`, ordinary least squares, or `huber`, the Huber loss, which counts a point's
residual squared up to HUBER_K robust standard deviations and linearly beyond, so that a few
outliers pull the line less. POINTS is a CSV file with columns x and y.
"""

import csv
import json
import statistics
import sys

HUBER_K = 1.345
"""The Huber option's setting: where the loss turns from squared to linear, in robust standard
deviations of the residuals. 1.345 is the usual choice."""


def weighted_line(xs: list[float], ys: list[float], ws: list[float]) -> tuple[float, float]:
    """The slope and intercept that minimise the weighted sum of squared residuals."""
    total = sum(ws)
    mx = sum(w * x for w, x in zip(ws, xs)) / total
    my = sum(w * y for w, y in zip(ws, ys)) / total
    sxy = sum(w * (x - mx) * (y - my) for w, x, y in zip(ws, xs, ys))
    sxx = sum(w * (x - mx) ** 2 for w, x in zip(ws, xs))
    slope = sxy / sxx
    return slope, my - slope * mx


def huber_line(xs: list[float], ys: list[float]) -> tuple[float, float]:
    """The Huber fit, by iteratively reweighted least squares from the least-squares line."""
    slope, intercept = weighted_line(xs, ys, [1.0] * len(xs))
    for _ in range(100):
        residuals = [y - (slope * x + intercept) for x, y in zip(xs, ys)]
        scale = statistics.median(abs(r) for r in residuals) / 0.6745 or 1.0
        limit = HUBER_K * scale
        ws = [1.0 if abs(r) <= limit else limit / abs(r) for r in residuals]
        new = weighted_line(xs, ys, ws)
        if abs(new[0] - slope) < 1e-12 and abs(new[1] - intercept) < 1e-12:
            break
        slope, intercept = new
    return slope, intercept


def main(method: str, points_path: str, output_path: str) -> None:
    with open(points_path, encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    xs, ys = [float(row["x"]) for row in rows], [float(row["y"]) for row in rows]
    if method == "ols":
        slope, intercept = weighted_line(xs, ys, [1.0] * len(xs))
    elif method == "huber":
        slope, intercept = huber_line(xs, ys)
    else:
        raise SystemExit(f"unknown method {method!r}: give ols or huber")
    fit = {"method": method, "points": len(xs), "slope": round(slope, 6), "intercept": round(intercept, 6)}
    with open(output_path, "w", encoding="utf-8") as stream:
        json.dump(fit, stream, indent=2)
        stream.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
