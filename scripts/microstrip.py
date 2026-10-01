"""Surface microstrip impedance (Hammerstad-Jensen with strip thickness correction).

Uncoated and static (no dispersion), as in Wadell's Transmission Line Design
Handbook; solder mask over the trace drops the impedance a few percent.
"""
import math

FREE_SPACE_IMPEDANCE = 376.730313668


def _air_impedance(u: float) -> float:
    f = 6 + (2 * math.pi - 6) * math.exp(-((30.666 / u) ** 0.7528))
    return FREE_SPACE_IMPEDANCE / (2 * math.pi) * math.log(f / u + math.sqrt(1 + 4 / u**2))


def _effective_permittivity(u: float, epsilon_r: float) -> float:
    a = (1 + math.log((u**4 + (u / 52) ** 2) / (u**4 + 0.432)) / 49
         + math.log(1 + (u / 18.1) ** 3) / 18.7)
    b = 0.564 * ((epsilon_r - 0.9) / (epsilon_r + 3)) ** 0.053
    return (epsilon_r + 1) / 2 + (epsilon_r - 1) / 2 * (1 + 10 / u) ** (-a * b)


def impedance(width: float, height: float, thickness: float, epsilon_r: float) -> float:
    """Characteristic impedance in ohms of a trace `width` wide and `thickness`
    thick, `height` above its reference plane; all lengths in the same units."""
    u = width / height
    t = thickness / height
    du_air = t / math.pi * math.log(1 + 4 * math.e / (t / math.tanh(math.sqrt(6.517 * u)) ** 2))
    du_dielectric = 0.5 * (1 + 1 / math.cosh(math.sqrt(epsilon_r - 1))) * du_air
    u_air = u + du_air
    u_dielectric = u + du_dielectric
    epsilon_eff = (_effective_permittivity(u_dielectric, epsilon_r)
                   * (_air_impedance(u_air) / _air_impedance(u_dielectric)) ** 2)
    return _air_impedance(u_dielectric) / math.sqrt(epsilon_eff)


def width_for_impedance(target: float, height: float, thickness: float,
                        epsilon_r: float) -> float:
    """Trace width giving `target` ohms, by bisection (impedance falls with width)."""
    low, high = height * 1e-3, height * 100
    for _ in range(100):
        middle = math.sqrt(low * high)
        if impedance(middle, height, thickness, epsilon_r) > target:
            low = middle
        else:
            high = middle
    return math.sqrt(low * high)
