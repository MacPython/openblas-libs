if [[ "${INTERFACE64}" == "1" ]]; then
    # python -m pip install --no-index --find-links dist scipy_openblas64
    python -m scipy_openblas64
    python -c "import scipy_openblas64; print(scipy_openblas64.get_pkg_config())"
else
    # python -m pip install --no-index --find-links dist scipy_openblas32
    python -m scipy_openblas32
    python -c "import scipy_openblas32; print(scipy_openblas32.get_pkg_config())"
fi