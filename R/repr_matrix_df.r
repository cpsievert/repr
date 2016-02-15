#' Tabular data representations
#' 
#' HTML and LaTeX representations of Matrix-like objects
#' 
#' @param obj  The matrix or data.frame to create a representation for
#' @param ...  ignored
#' @param colspec  The colspec for the LaTeX table. The default is given by the option \code{repr.matrix.latex.colspec}
#' 
#' @seealso \link{repr-options} for \code{repr.matrix.latex.colspec}
#' 
#' @aliases repr_html.matrix repr_html.data.frame repr_latex.matrix repr_latex.data.frame
#' @name repr_*.matrix/data.frame
#' @include utils.r
NULL

ellip.h <- '\u22EF'
ellip.v <- '\u22EE'
ellip.d <- '\u22F1'

ellipses <- c(ellip.h, ellip.v, ellip.d)

ellip.limit.vec <- function(v, num, ellip) {
	stopifnot(num >= 2L)
	
	left  <- seq_len(ceiling(num / 2))
	right <- seq.int(length(v) - floor(num / 2) + 1L, length(v))
	
	# fix factors not having the appropriate levels
	if (is.factor(v)) {
		levels(v) <- c(levels(v), ellipses)
	}
	
	c(v[left], ellip, v[right])
}

ellip.limit.arr <- function(
	a,
	rows = getOption('repr.matrix.max.rows'),
	cols = getOption('repr.matrix.max.cols')
) {
	stopifnot(rows >= 2L, cols >= 2L)
	
	left   <- seq_len(ceiling(cols / 2))
	right  <- seq.int(ncol(a) - floor(cols / 2) + 1L, ncol(a))
	top    <- seq_len(ceiling(rows / 2))
	bottom <- seq.int(nrow(a) - floor(rows / 2) + 1L, nrow(a))
	
	# fix columns that won't like ellipsis being inserted
	# TODO(karldw): Make this column indexing work with data.table as well.
	if (is.data.frame(a)) {
		for (c in seq_len(ncol(a))) {
			if (is.factor(a[, c])) {
				# Factors: add ellipses to levels
				levels(a[, c]) <- c(levels(a[, c]), ellipses)
			} else if (inherits(a[, c], "Date")) {
				# Dates: convert to plain strings
				a[, c] <- as.character(a[, c])
			}
		}
	}
	
	if (rows >= nrow(a) && cols >= ncol(a)) {
		return(a)
	} else if (rows < nrow(a) && cols < ncol(a)) {
		ehf <- factor(ellip.h, levels = ellipses)
		rv <- rbind(
			cbind(a[   top, left], ehf, a[   top, right], deparse.level = 0),
			ellip.limit.vec(rep(ellip.v, ncol(a)), cols, ellip.d),
			cbind(a[bottom, left], ehf, a[bottom, right], deparse.level = 0),
			deparse.level = 0)
	} else if (rows < nrow(a) && cols >= ncol(a)) {
		rv <- rbind(a[top, , drop = FALSE], ellip.v, a[bottom, , drop = FALSE], deparse.level = 0)
	} else if (rows >= nrow(a) && cols < ncol(a)) {
		# TODO(karldw): Make this column indexing work with data.table as well.
		rv <- cbind(a[, left, drop = FALSE], ellip.h, a[, right, drop = FALSE], deparse.level = 0)
	}

	if (rows < nrow(a)) {
		# If there were no rownames before, as is often true for matrices, assign them.
		if (is.null(rownames(rv)))
			rownames(rv) <- c(top, ellip.v, bottom)
		else
			rownames(rv)[[ top[[length(top) ]] + 1L]] <- ellip.v
	}

	if (cols < ncol(a)) {
		if (is.null(colnames(rv)))
			colnames(rv) <- c(left, ellip.h, right)
		else
			colnames(rv)[[left[[length(left)]] + 1L]] <- ellip.h
	}

	rv
}

# HTML --------------------------------------------------------------------

repr_matrix_generic <- function(
	x,
	wrap,
	header.wrap, corner, head,
	body.wrap, row.wrap, row.head,
	cell, last.cell = cell
) {
	has.rownames <- !is.null(rownames(x))
	has.colnames <- !is.null(colnames(x))
	
	x <- ellip.limit.arr(x)
	
	header <- ''
	if (has.colnames) {
		headers <- sprintf(head, colnames(x))
		if (has.rownames) headers <- c(corner, headers)
		header <- sprintf(header.wrap, paste(headers, collapse = ''))
	}
	
	rows <- lapply(seq_len(nrow(x)), function(r) {
		row <- x[r, ]
		cells <- sprintf(cell, format(row))
		if (has.rownames) {
			row.head <- sprintf(row.head, rownames(x)[[r]])
			cells <- c(row.head, cells)
		}
		sprintf(row.wrap, paste(cells, collapse = ''))
	})
	
	body <- sprintf(body.wrap, paste(rows, collapse = ''))
	
	sprintf(wrap, header, body)
}


#' @name repr_*.matrix/data.frame
#' @export
repr_html.matrix <- function(obj, ...) repr_matrix_generic(
	obj,
	'<table>\n%s%s</table>\n',
	'<thead><tr>%s</tr></thead>\n', '<th></th>',
	'<th scope=col>%s</th>',
	'<tbody>\n%s</tbody>\n', '\t<tr>%s</tr>\n', '<th scope=row>%s</th>',
	'<td>%s</td>')

#' @name repr_*.matrix/data.frame
#' @export
repr_html.data.frame <- repr_html.matrix



# LaTeX -------------------------------------------------------------------



#' @name repr_*.matrix/data.frame
#' @export
repr_latex.matrix <- function(obj, ..., colspec = getOption('repr.matrix.latex.colspec')) {
	cols <- paste0(paste(rep(colspec$col, ncol(obj)), collapse = ''), colspec$end)
	if (!is.null(rownames(obj)))
		cols <- paste0(colspec$row.head, cols)
	obj <- latex.escape.names(obj)

	# Using apply here will convert a data.frame to matrix, as well as escaping
	# any columns with LaTeX specials, but only go through the hassle if there are
	# actually things to escape.
	if (any(apply(obj, 2L, any.latex.specials))) {
		obj_rownames <- rownames(obj)
		obj <- apply(obj, 2L, latex.escape.vec)
		# If obj only has one row, apply will collapse it to a vector.
		# That's a pain, so we'll recast it as a matrix.
		if (is.null(dim(obj)))
			obj <- matrix(obj, nrow=1L)
		rownames(obj) <- obj_rownames  # apply throws away row names.
	}

	r <- repr_matrix_generic(
		obj,
		sprintf('\\begin{tabular}{%s}\n%%s%%s\\end{tabular}\n', cols),
		'%s\\\\\n\\hline\n', '  &', ' %s &',
		'%s', '\t%s\\\\\n', '%s &',
		' %s &')

	#todo: remove this quick’n’dirty post processing
	gsub(' &\\', '\\', r, fixed=TRUE)
}

#' @name repr_*.matrix/data.frame
#' @export
repr_latex.data.frame <- repr_latex.matrix
# Text -------------------------------------------------------------------



#' @name repr_*.matrix/data.frame
#' @export
repr_text.matrix <- function(obj, ...)
	paste(capture.output(print(ellip.limit.arr(obj))), collapse = '\n')

#' @name repr_*.matrix/data.frame
#' @export
repr_text.data.frame <- repr_text.matrix
