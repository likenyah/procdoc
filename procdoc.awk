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
# warning - Write a warning message to man:stderr(3).
#
# @msg: Message to write.
#
# @return: None.
function warning(msg)
{
	printf("warning: %s\n", msg) >"/dev/stderr"
}

##
# warningfl - Write a warning message with file information to man:stderr(3).
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
# error - Write an error message to man:stderr(3).
#
# @msg: Message to write.
#
# @return: None.
function error(msg)
{
	printf("error: %s\n", msg) >"/dev/stderr"
}

##
# errorfl - Write an error message with file information to man:stderr(3).
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
# fatal - Write an error message to man:stderr(3) and exit.
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
# fatalfl - Write an error message with file information to man:stderr(3) and exit.
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
# json_string_escape - Properly escape invalid JSON string content.
#
# @s: String to work on.
#
# @return: String suitable for substitution into a JSON string.
function json_string_escape(s)
{
	# RFC 8259 says the following:
	#
	# > All Unicode characters may be placed within the quotation marks,
	# > except for the characters that MUST be escaped: quotation mark,
	# > reverse solidus, and the control characters (U+0000 through
	# > U+001F).
	#
	# However, we assume that we are only likely to see the following raw
	# characters in text we care about:
	#
	# * U+0000 NUL
	# * U+0007 BEL
	# * U+0008 BS
	# * U+0009 HT
	# * U+000B VT
	# * U+000C FF
	# * U+000D CR
	# * U+0021 Quotation Mark
	# * U+005C Reverse Solidus
	#
	# Note that LF is absent here, since we consume the input in a
	# line-wise manner.
	gsub(/\\/, "\\\\", s)
	gsub(/"/, "\\\"", s)
	gsub(/\0/, "\\0", s)
	gsub(//, "\\a", s)
	gsub(//, "\\b", s)
	gsub(//, "\\f", s)
	gsub(//, "\\r", s)
	gsub(/	/, "\\t", s)
	gsub(//, "\\v", s)

	# Workaround for nawk(1) matching the terminating null byte of a
	# string.
	sub(/\\0$/, "", s)

	return s
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
# @delim:  Delimiter array, indexable by `delim[type, member]`.
# @member: Member name of the delimiter to match against.
# @r:      Type data return array. `r["type"]` will be set to that of the
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
# @fileinfo:     Array containing the path to -- `fileinfo["path"]` -- and
#                current line number of -- `fileinfo["lineno"]` -- the file.
#                The line number will be incremented by the number of lines
#                consumed by block_read().
# @blocks:       Array of blocks to append to. The meta-entry
#                `blocks["@blocks"]` is expected to store the number of blocks
#                currently in the array and will be incremented upon
#                successfully reading a block.
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
# block_write - Write a JSON block to an output.
#
# @output:  Output file to write to.
# @blocks:  Array of blocks to read from.
# @id:      Identifier of the block to write to the output file.
# @content: Blocktype-specific content. For generic blocks, this is just an
#           array of all lines in the block with their lead stripped. For
#           functions, see block_process_function().
#
# @return: None.
function block_write(output, blocks, id, content,                         i, s)
{
	s = sprintf("{\"id\":%d", id)
	s = sprintf("%s,\"type\":\"%s\"", s, blocks[id, "type"])
	s = sprintf("%s,\"markup\":\"%s\"", s, blocks[id, "markup"])
	s = sprintf("%s,\"file\":\"%s\"", s, json_string_escape(blocks[id, "file"]))
	s = sprintf("%s,\"lines\":{\"initial\":%d,\"total\":%d}",
	            s, blocks[id, "init"], blocks[id, "lines"])

	if (blocks[id, "type"] == "generic") {
		s = sprintf("%s,\"content\":[%s]", s, content)
	} else {
		s = sprintf("%s,\"content\":{", s)

		s = sprintf("%s\"name\":\"%s\"",
		            s, json_string_escape(content["name"]))

		s = sprintf("%s,\"short-description\":\"%s\"",
		            s, json_string_escape(content["shortdesc"]))

		if (content["members"] > 0) {
			s = sprintf("%s,\"members\":[", s)

			for (i = 0; i < content["members"]; i++) {
				s = sprintf("%s{\"name\": \"%s\"",
				            s,
				            content["member", i, "name"])

				s = sprintf("%s,\"description\":\"%s\"},",
				            s,
				            json_string_escape(content["member", i, "desc"]))
			}

			sub(/,$/, "", s)
			s = sprintf("%s]", s)
		} else {
			s = sprintf("%s,\"members\":[]", s)
		}

		if (content["paragraphs"] > 0) {
			s = sprintf("%s,\"description\":[", s)

			for (i = 0; i < content["paragraphs"]; i++) {
				s = sprintf("%s{\"heading\": \"%s\"",
				            s,
				            content["paragraph", i, "heading"])

				s = sprintf("%s,\"paragraph\":\"%s\"},",
				            s,
				            json_string_escape(content["paragraph", i, "desc"]))
			}

			sub(/,$/, "", s)
			s = sprintf("%s]", s)
		} else {
			s = sprintf("%s,\"description\":[]", s)
		}

		s = sprintf("%s}", s)
	}

	s = sprintf("%s}", s)
	printf("%s\n", s) >output
}

##
# block_process_function - Process a function block and write it to and output.
#
# @output: Output file to write to.
# @blocks: Array of blocks to read from.
# @id:     Identifier of the block to process.
#
# @return: None.
function block_process_function(output, blocks, id,   a, cl, nl, i, j, k, l, t)
{
	a["name"] = ""
	a["shortdesc"] = ""
	a["members"] = 0
	a["paragraphs"] = 0

	i = 0
	t = blocks[id, "lines"]

	cl = ""
	nl = ""

	while (i < t && blocks[id, "line", i] ~ /^[[:space:]]*$/)
		i++

	if (i == t) {
		warningfl(blocks[id, "file"], blocks[id, "init"] + 1 + i,
			  "empty function block")
	}

	# TODO: Handle enum/struct/etc <2021-08-19, Alex Minghella>
	cl = blocks[id, "line", i]
	if (cl ~ /^[[:alpha:]]+[[:space:]]+[[:alnum:]:_+-][[:alnum:]:_+-]+/) {
		if (cl !~ /^function/) {
			warningfl(blocks[id, "file"],
			          blocks[id, "init"] + 1 + i,
			          "ignoring non-function block")

			return
		} else {
			sub(/^function[[:space:]]+/, "", cl)
		}
	}

	if (match(cl, /^[[:alnum:]:_+-]+/)) {
		a["name"] = substr(cl, RSTART, RLENGTH)
	} else {
		errorfl(blocks[id, "file"], blocks[id, "init"] + 1 + i,
		        "missing title in function block")

		return
	}

	# A short description is optional.
	if (match(blocks[id, "line", i], /[[:space:]]+-[[:space:]]*.+$/)) {
		a["shortdesc"] = substr(cl, RSTART, RLENGTH)
		sub(/^[[:space:]]+-[[:space:]]*/, "", a["shortdesc"])
	}

	# Okay, we're done with the initial line. Eat through the rest of the
	# block's content.
	while (++i < t) {
		j = a["members"]
		k = a["paragraphs"]

		cl = blocks[id, "line", i]
		nl = blocks[id, "line", i + 1]
		sub(/^[[:space:]]*/, "", cl)
		sub(/^[[:space:]]*/, "", nl)

		if (match(cl, /^@[[:alnum:]._-]+:/)) {
			if (cl ~ /^@(return):/)
				a["member", j, "name"] = substr(cl, RSTART, RLENGTH - 1)
			else
				a["member", j, "name"] = substr(cl, RSTART + 1, RLENGTH - 2)

			m = substr(cl, RLENGTH + 1)
			sub(/^[[:space:]]+/, "", m)

			while (i < t \
			       && nl != "" \
			       && nl !~ /^@[[:alnum:]._-]+:/) {
				i++
				cl = blocks[id, "line", i]
				nl = blocks[id, "line", i + 1]
				sub(/^[[:space:]]*/, "", cl)
				sub(/^[[:space:]]*/, "", nl)

				m = sprintf("%s %s", m, cl)
			}

			sub(/^[[:space:]]+/, "", m)
			a["member", j, "desc"] = m
			a["members"]++
		} else if (match(cl, /^([[:alnum:]]+:)?|^[[:alnum:] ]+:$/) && cl != "") {
			# If no heading matches, we have RSTART = 1 and
			# RLENGTH = 0, which gives us an empty heading and the
			# whole line in m.
			a["paragraph", k, "heading"] = substr(cl, RSTART, RLENGTH - 1)

			m = substr(cl, RLENGTH + 1)
			sub(/^[[:space:]]+/, "", m)

			while (i < t && nl != "") {
				i++
				cl = blocks[id, "line", i]
				nl = blocks[id, "line", i + 1]
				sub(/^[[:space:]]*/, "", cl)
				sub(/^[[:space:]]*/, "", nl)

				m = sprintf("%s %s", m, cl)
			}

			sub(/^[[:space:]]+/, "", m)
			a["paragraph", k, "desc"] = m
			a["paragraphs"]++
		}
	}

	block_write(output, blocks, id, a)
}

##
# block_process_generic - Process a generic block and write it to an output.
#
# @output: Output file to write to.
# @blocks: Array of blocks to read from.
# @id:     Identifier of the block to process.
#
# @return: None.
function block_process_generic(output, blocks, id,                        c, i)
{
	c = ""
	if (blocks[id, "lines"] > 0) {
		c = sprintf("%s\"%s\"", c,
		            json_string_escape(blocks[id, "line", 0]))

		for (i = 1; i < blocks[id, "lines"]; i++) {
			c = sprintf("%s,\"%s\"", c,
			            json_string_escape(blocks[id, "line", i]))
		}

	}

	block_write(output, blocks, id, c)
}

##
# getopt - POSIX man:getopt(3) implementation.
#
# @argc:      See man:awk(1) ARGC.
# @argv:      See man:awk(1) ARGV.
# @optstring: See man:getopt(3).
#
# @return: Next option character as a string, on success. If the next option
#          character is not in optstring, then `"?"` if `":"` was not the first
#          character in optstring, else `":"`. If there are no more options or
#          the end of <<argv>> was encountered, then -1.
#
# This implementation is loosely based on the musl libc implementation of
# man:getopt(3). Some GNU extensions are supported: optional option arguments
# may be specified in optstring with two colons; an initial "-" in optstring
# will cause getopt() to treat all non-options as option arguments to 1 (the
# integer, not the character); and an inital "+" is supported but ignored. (We
# don't permute <<argv>> but this may be useful to implement
# man:getopt_long(3).)
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
		type = blocks[i, "type"]

		if (type == "function" && f) {
			block_process_function(o, blocks, i)
		} else if (type == "generic" && g) {
			block_process_generic(o, blocks, i)
		}
	}

	return 0
}

BEGIN {
	exit(main(ARGC, ARGV))
}
