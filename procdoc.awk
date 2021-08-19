#! /usr/bin/env -S awk -f
# SPDX-License-Identifier: 0BSD
#
# Copyright © 2021 Alex Minghella <a@minghella.net>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# -----------------------------------------------------------------------------

##
# warning - Write a warning to stderr(3).
#
# @msg: Message to write.
#
# @return: None.
function warning(msg)
{
	printf("warning: %s\n", msg) >"/dev/stderr"
}

##
# warningfl - Write an error message with file information to stderr(3) and exit.
#
# @file: File in which the error occurred.
# @line: Line number on which the error occurred.
# @msg:  Message to write.
#
# @return: None.
function warningfl(file, line, msg)
{
	printf("warning:%s:%d: %s\n", file, line, msg) >"/dev/stderr"
}

##
# error - Write an error message to stderr(3).
#
# @msg: Message to write.
#
# @return: None.
function error(msg)
{
	printf("error: %s\n", msg) >"/dev/stderr"
}

##
# errorfl - Write an error message with file information to stderr(3) and exit.
#
# @file: File in which the error occurred.
# @line: Line number on which the error occurred.
# @msg:  Message to write.
#
# @return: None.
function errorfl(file, line, msg)
{
	printf("error:%s:%d: %s\n", file, line, msg) >"/dev/stderr"
}

##
# fatal - Write an error message to stderr(3) and exit.
#
# @msg: Message to write.
#
# @return: None. (Does not return.)
function fatal(msg)
{
	printf("fatal: %s\n", msg) >"/dev/stderr"
	exit(1)
}

##
# fatalfl - Write an error message with file information to stderr(3) and exit.
#
# @file: File in which the error occurred.
# @line: Line number on which the error occurred.
# @msg:  Message to write.
#
# @return: None. (Does not return).
function fatalfl(file, line, msg)
{
	printf("fatal:%s:%d %s\n", file, line, msg) >"/dev/stderr"
	exit(1)
}

##
# filetype_get - Guess the type of a given file based on its name.
#
# @file: Path to file.
# @dfl:  Fallback to return if a filetype could not be determined. May be
#        empty, in which case "unknown" will be returned.
#
# @return: Filetype string. (ie. The final extension of the filename.)
function filetype_get(file, dfl)
{
	if (match(file, /\.[^\/.]*$/))
		return substr(file, RSTART + 1, RLENGTH - 1)
	else
		return dfl ? dfl : "unknown"
}

##
# delim_get - Retrieve a set of delimiters appropriate for a given filetype.
#
# @delim:    Array to store delimiters in.
# @filetype: Filetype to get delimiters for.
#
# @return: None.
function delim_get(delim, filetype)
{
	if (filetype ~ /^[gn]?awk$/) {
		delim["generic", "head"] = "^##"
		delim["generic", "lead"] = "^# ?"
		delim["generic", "foot"] = "^##$"

		delim["function", "head"] = "^##$"
		delim["function", "lead"] = "^# ?"
		delim["function", "foot"] = "^function[[:space:]]+[[:alnum:]:_+-]+[[:space:]]*\\([^)]*\\)"
	} else if (filetype ~ /^((b|d)?a|[kz])?sh$/) {
		delim["generic", "head"] = "^##"
		delim["generic", "lead"] = "^# ?"
		delim["generic", "foot"] = "^##$"

		delim["function", "head"] = "^##$"
		delim["function", "lead"] = "^# ?"
		delim["function", "foot"] = "^(function[[:space:]]+)?[[:alnum:]:_+-]+[[:space:]]*\\(\\)"
	} else if (filetype ~ /^[ch](pp|\+\+|xx)?|C$/) {
		delim["generic", "head"] = "^\\/\\*\\*"
		delim["generic", "lead"] = "^\\* ?"
		delim["generic", "foot"] = "^\\*\\*\\/$"

		delim["function", "head"] = "^\\/\\*\\*"
		delim["function", "lead"] = "^\\* ?"
		delim["function", "foot"] = "^\\*\\/"
	} else {
		delim["generic", "head"] = "^##"
		delim["generic", "lead"] = "^# ?"
		delim["generic", "foot"] = "^##$"

		# This is undefined as a fallback.
		delim["function", "head"] = ""
		delim["function", "lead"] = ""
		delim["function", "foot"] = ""
	}
}

##
# delim_match - Attempt to match the current input line against a delimiter.
#
# @delim:  Delimiter array, indexable by delim[type, member].
# @member: Member name of the delimiter to match against.
# @r:      Type data return array. r["type"] will be set to that of the
#          matching delimiter type.
#
# @return: 1 if the specified delimiter was matched, else 0.
function delim_match(delim, member, r)
{
	if (delim["generic", member] && $0 ~ delim["generic", member]) {
		r["type"] = "generic"
		return 1
	} else if (delim["function", member] && $0 ~ delim["function", member]) {
		r["type"] = "function"
		return 1
	} else {
		r["type"] = ""
		return 0
	}
}

##
# block_read - Read the next documentation block from a given file.
#
# @fileinfo:     Array containing the path to - fileinfo["path"] - and current
#                line number of - fileinfo["lineno"] - the file. The line
#                number will be incremented by the number of lines consumed by
#                block_read().
# @blocks:       Array of blocks to append to. The meta-entry blocks["@blocks"]
#                is expected to store the number of blockes currently in the
#                array and will be incremented upon successfully reading a
#                block.
# @default_type: Default filetype to use if it cannot be determined by the
#                filename.
#
# @return: 1 if a block was successfully read from the specified file, 0 if the
#          end of the file was reached, -1 if there was an I/O error.
function block_read(fileinfo, blocks, default_type,    d, f, i, id, n, r, s, t)
{
	# File information.
	f = fileinfo["file"]
	n = fileinfo["lineno"]

	# Identifier for this block.
	id = blocks["@blocks"]

	# Number of lines in this block.
	i = 0

	# State, or whether we're currently not in a block. (ie. Skipping.)
	s = 1

	# Block type. This must be an array in order to get anything back from
	# delim_match().
	t["type"] = ""

	# Overall return value.
	r = 1

	delim_get(d, filetype_get(f, default_type))
	while ((e = (getline <f)) == 1) {
		sub(/^[[:space:]]+/, "", $0)

		if (s && !delim_match(d, "head", t)) {
			n++
			continue
		} else if (s && delim_match(d, "head", t)) {
			blocks[id, "file"] = f
			blocks[id, "init"] = n
			blocks[id, "type"] = t["type"]
			s = 0
			n++

			# We may have a markup tag for generic blocks since we
			# don't define any special format for them.
			if (t["type"] == "generic" && match($0, /![[:alnum:]]+$/))
				blocks[id, "markup"] = substr($0, RSTART + 1, RLENGTH - 1)
			else
				blocks[id, "markup"] = "none"

			continue
		} else if (!s && delim_match(d, "foot", t)) {
			# Allow users to force function blocks. This covers
			# cases where matching is difficult or unreliable.
			# For example, to avoid duplicating documentation for
			# functions conditionally defined for big- or
			# little-endian that otherwise have identical
			# semantics.
			if (blocks[id, "markup"] == "function") {
				t["type"] = "function"
			}

			blocks[id, "type"] = t["type"]
			n++

			# Function blocks have special markup. We'd also like
			# to inform the user of the starting line of the
			# current block, since that's where the error is.
			if (t["type"] == "function") {
				if (blocks[id, "markup"] !~ /^(function|none)$/)
					warningfl(f, blocks[id, "init"], "function blocks may not have a markup tag")

				blocks[id, "markup"] = "function"
			}

			break
		}

		# Valid blocks do not contain lines which do not have a lead.
		if (!delim_match(d, "lead", t)) {
			warningfl(f, n, "unclosed block")
			n++
			break
		}

		# Eat the lead from this line, save the resulting string, and
		# update our line number.
		sub(d[t["type"], "lead"], "", $0)
		blocks[id, "line", i++] = $0
		n++
	}

	# Record the number of lines in this block and update the caller's
	# record of the current line number.
	blocks[id, "lines"] = i
	fileinfo["lineno"] = n

	if (e == -1) {
		errorfl(f, n, "I/O error")
		r = -1
	} else if (e == 0) {
		r = 0
	}

	if (r == 1)
		blocks["@blocks"]++

	return r
}

##
# getopt - POSIX getopt(3) implementation.
#
# @argc:      See awk(1) ARGC.
# @argv:      See awk(1) ARGV.
# @optstring: See getopt(3).
#
# @return: Next option character as a string, on success. If the next option
#          character is not in optstring, then "?" if ":" was not the first
#          character in optstring, else ":". If there are no more options or
#          the end of argv was encountered, then -1.
#
# This implementation is loosely based on the musl libc implementation of
# getopt(3). Some GNU extensions are supported: optional option arguments may
# be specified in optstring with two colons; an initial "-" in optstring will
# cause getopt() to treat all non-options as option arguments to 1 (the
# integer, not the character); and an inital "+" is supported but ignored. (We
# don't permute argv but this may be useful to implement getopt_long(3).)
function getopt(argc, argv, optstring,                                    c, i)
{
	if (!optind || optreset) {
		__getopt_optpos = 0;
		optind = 1
		optreset = 0
	}

	if (optind >= argc || !argv[optind])
		return -1

	if (argv[optind] !~ /^-/) {
		if (optstring ~ /^-/) {
			optarg = argv[optind++]
			return 1
		}

		return -1
	}

	if (argv[optind] ~ /^-$/)
		return -1

	if (argv[optind] ~ /^--$/) {
		optind++
		return -1
	}

	if (!__getopt_optpos)
		__getopt_optpos = 1

	c = substr(argv[optind], ++__getopt_optpos, 1)

	if (substr(argv[optind], __getopt_optpos + 1) == "") {
		optind++
		__getopt_optpos = 0
	}

	if (optstring ~ /^[+-]/)
		optstring = substr(optstring, 2)

	if ((i = index(optstring, c)) == 0 || c == ":") {
		optopt = c

		if (optstring !~ /^:/ && opterr) {
			printf("%s: error: invalid option: -%c\n",
			       argv[0], c) >"/dev/stderr"
		}

		return "?"
	}

	if (substr(optstring, i + 1, 1) == ":") {
		optarg = ""

		if (substr(optstring, i + 2, 1) != ":" || __getopt_optpos) {
			optarg = substr(argv[optind++], __getopt_optpos + 1)
			__getopt_optpos = 0
		}

		if (optind > argc) {
			optopt = c

			if (optstring ~ /^:/)
				return ":"

			if (opterr) {
				printf("%s: error: option requires argument: -%c\n",
				       argv[0], c) >"/dev/stderr"
			}

			return "?"
		}
	}

	return c;
}

function main(argc, argv,           blocks, fi, opt, type, e, f, g, h, i, o, v)
{
	h = \
	"usage: awk -f </path/to/procdoc.awk> -- [-fghotv] [<file>]...\n" \
	"\n" \
	"Options:\n" \
	" -f           Output only function blocks.\n" \
	" -g           Output only generic blocks.\n" \
	" -h           Display this help message.\n" \
	" -o <file>    Write output to <file>.\n" \
	" -t <type>    Use <type> as the default filetype.\n" \
	" -v           Display version information.\n"

	f = 0
	g = 0
	o = ""
	t = ""
	v = "0.1.0"

	opt = 0
	while ((opt = getopt(argc, argv, ":hfgo:t:v")) != -1) {
		if (opt == "f") {
			f = 1
			g = 0
		} else if (opt == "g") {
			f = 0
			g = 1
		} else if (opt == "h") {
			printf("%s", h)
			return 0
		} else if (opt == "o") {
			o = optarg
		} else if (opt == "t") {
			t = optarg
		} else if (opt == "v") {
			printf("procdoc version %s\n", v)
			return 0
		} else if (opt == ":") {
			fatal(sprintf("option requires argument: -%c", optopt))
		} else {
			fatal(sprintf("invalid option: -%c", optopt))
		}
	}

	# Output both block types by default.
	if (!f && !g) {
		f = 1
		g = 1
	}

	blocks["@blocks"] = 0

	while (optind < argc) {
		fi["file"] = argv[optind++]
		fi["lineno"] = 1

		do {
			e = block_read(fi, blocks, t)
		} while (e == 1)

		if (e == 0)
			close(fi["file"])
	}

	if (!o || o == "-")
		o = "/dev/stdout"

	for (i = 0; i < blocks["@blocks"]; i++) {
		if (blocks[i, "type"] == "function" && !f)
			continue
		else if (blocks[i, "type"] == "generic" && !g)
			continue

		printf("block %d, %s (%s:%d)\nmarkup: %s\n", i,
		       blocks[i, "type"], blocks[i, "file"],
		       blocks[i, "init"], blocks[i, "markup"]) >o

		for (j = 0; j < blocks[i, "lines"]; j++)
			printf("%2d: %s\n", j, blocks[i, "line", j]) >o
	}

	return 0
}

BEGIN {
	exit(main(ARGC, ARGV))
}
