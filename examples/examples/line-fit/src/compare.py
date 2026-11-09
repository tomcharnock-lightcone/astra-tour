"""Compare two line fits, as JSON: python3 compare.py OLS_FIT HUBER_FIT OUTPUT.

Each fit is a JSON file from fit.py. The comparison gives both lines and how far the Huber line
is from the least-squares one, in slope and intercept.
"""

import json
import sys


def main(ols_path: str, huber_path: str, output_path: str) -> None:
    fits = {}
    for path in (ols_path, huber_path):
        with open(path, encoding="utf-8") as stream:
            fit = json.load(stream)
        fits[fit["method"]] = {"slope": fit["slope"], "intercept": fit["intercept"]}
    ols, huber = fits["ols"], fits["huber"]
    comparison = {
        "ols": ols,
        "huber": huber,
        "slope_difference": round(huber["slope"] - ols["slope"], 6),
        "intercept_difference": round(huber["intercept"] - ols["intercept"], 6),
    }
    with open(output_path, "w", encoding="utf-8") as stream:
        json.dump(comparison, stream, indent=2)
        stream.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
