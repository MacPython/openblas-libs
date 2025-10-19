from setuptools import setup
from setuptools.dist import Distribution
from wheel.bdist_wheel import bdist_wheel as _bdist_wheel


class BinaryDistribution(Distribution):
    def has_ext_modules(self):
        return True


class bdist_wheel(_bdist_wheel):
    def get_tag(self):
        return "py3", "none", _bdist_wheel.get_tag(self)[2]


setup(
    distclass=BinaryDistribution,
    cmdclass={"bdist_wheel": bdist_wheel},
)
