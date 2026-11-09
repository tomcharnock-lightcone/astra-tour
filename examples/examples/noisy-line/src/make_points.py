"""Write noisy points around a straight line, as CSV: python3 make_points.py CONFIG OUTPUT.

CONFIG is a JSON file with `slope`, `intercept`, `noise` (the standard deviation of the
Gaussian noise), `points`, `outliers` (how many of the points are pushed well above the line)
and `seed`. The same CONFIG always gives the same bytes.
"""

import json
import math
import random
import sys


def gauss(rng: random.Random) -> float:
    """A standard normal draw by the Box-Muller transform, from `rng.random()` alone, so that
    every Python version gives the same numbers."""
    u, v = 1.0 - rng.random(), rng.random()
    return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v)


def main(config_path: str, output_path: str) -> None:
    with open(config_path, encoding="utf-8") as stream:
        config = json.load(stream)
    rng = random.Random(config["seed"])
    xs = sorted(10.0 * rng.random() for _ in range(config["points"]))
    ys = [config["slope"] * x + config["intercept"] + config["noise"] * gauss(rng) for x in xs]
    for index in rng.sample(range(len(xs)), config["outliers"]):
        ys[index] += 8.0 + 4.0 * rng.random()
    with open(output_path, "w", encoding="utf-8") as stream:
        stream.write("x,y\n")
        for x, y in zip(xs, ys):
            stream.write(f"{x:.6f},{y:.6f}\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
