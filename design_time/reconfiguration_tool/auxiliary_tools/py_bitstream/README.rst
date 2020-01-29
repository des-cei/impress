PY_BITSTREAM
============

A Python framework for analyzing Xilinx's ``.bit`` bitstreams
and extracting partial bitstreams.


Getting started
---------------

In order to launch the graphical application to analyze and extract bitstreams,
run the ``gui.bat`` program (Windows) or the ``gui.py`` Python script
(Linux/Mac; requires Python 2.7 with Tkinter).


Project contents
----------------

``tools/bitstream.py``
    This is the core of the project.  tools/bitstream.py contains the
    definition of the Bitstream class, with methods to parse and process
    bitstream files.

``fpgas/``
    Individual definitions of different FPGAs, including both
    generic definition files (``virtex5.py``, ``series7.py``...)
    and specific FPGA models (``5vlx110tff1136.py``, ``7z020clg484.py``...).
    In order to extract a partial bitstream, you need a .py file corresponding
    to that FPGA model.  If such a file is not present, you will have to
    create it yourself.  These files have a very simple syntax (which was
    the main motivation for writing this project in Python).

``examples/``
    A couple of example bitstreams for some common development boards.

``portable_python/``
    This directory contains a portable distribution of Python for Windows,
    so that you don't need to install Python if you don't already have it.
    Linux and Mac users will need to have Python 2.7 installed
    (maybe 2.6 is enough, though).

``extract.py``
    The very first application developed using this framework!
    This is a very simple (and unsafe) command line application that extracts
    a partial bitstream from a .bit file.  You probably want to run the
    graphical application instead (gui.py), but this program could come in
    handy for batch conversions of multiple bitstreams.

``gui.py``
    Graphical interface that allows viewing instructions and extracting
    partial bitstreams.

``interactive.py``
    An interactive Python shell, with the ``tools.bitstream`` module and
    the bitstreams in ``examples/`` preloaded.  Commands beginning with ``!``
    will be passed to the system shell (e.g. ``!ls`` will list the current
    directory in Linux).  This interactive shell has history and autocomplete
    features provided by *readline* in case it's available.

``extract.bat``, ``gui.bat``, ``interactive.bat``
    Windows batch wrappers that call the Python interpreter located in
    ``portable_python/`` with the corresponding ``.py`` file and any
    extra command line argument, so that the programs can be run on Windows
    by just double-clicking the .bat.

``README.rst``
    This file.
