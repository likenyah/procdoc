# procdoc

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/E1E65IUF4)

## Overview

**procdoc** [ **-fghv** ] [ **-f** _format_ ] [ **-o** _file_ ] [ **-t** _type_ ] [ _file_ ]...

**procdoc** [ **-fghv** ] [ **-f** _format_ ] [ **-i** _file_ ] [ **-o** _file_ ] [ **-t** _type_ ]

**awk** **-f** _/path/to/procdoc.awk_ **--** [ **-fghv** ] [ **-o** _file_ ] [ **-t** _type_ ] [ _file_ ]...

A tool for extracting documentation from marked comments in source code files.
A smaller hammer for a smaller nail than tools like [Doxygen][url-doxygen] and
[Sphinx][url-sphinx]. Vaguely inspired by the Linux kernel's function
documentation comment format.

## Dependencies

Utilities specified by [POSIX.1-2017][url-posix], particularly
[**awk**(1)][url-awk] and [**sh**(1)][url-sh].

[url-awk]: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html
[url-doxygen]: https://www.doxygen.nl/index.html
[url-posix]: https://pubs.opengroup.org/onlinepubs/9699919799
[url-sh]: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sh.html
[url-sphinx]: https://www.sphinx-doc.org/en/master
