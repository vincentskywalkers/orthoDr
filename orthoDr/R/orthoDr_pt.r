#' @title orthoDr_pm model
#' @name orthoDr_pm
#' @description The "Direct Learning & Pseudo-direct Learning" Method for personalized medicine.
#' @param x A matrix or data.frame for features (continuous only).
#' @param a A vector of observed dose
#' @param r A vector of observed reward
#' @param ndr A dimension structure
#' @param B.initial Initial \code{B} values. Will use the counting process based SIR model \link[orthoDr]{CP_SIR} as the initial if leaving as \code{NULL}.
#' If specified, must be a matrix with \code{ncol(x)} rows and \code{ndr} columns. Will be processed by Gram-Schmidt if not orthogonal
#' @param bw A Kernel bandwidth, assuming each variables have unit variance
#' @param lambda A GCV penalty for the kernel ridge regression
#' @param K A number of grids in the range of dose
#' @param method A method the user will implement
#' @param keep.data Should the original data be kept for prediction
#' @param control A list of tuning variables for optimization. \code{epsilon} is the size for numerically appriximating the gradient. For others, see Wen and Yin (2013).
#' @param maxitr Maximum number of iterations
#' @param ncore the number of cores for parallel computing
#' @param verbose Should information be displayed
#' @return A \code{orthoDr} object; a list consisting of
#' \item{B}{The optimal \code{B} value}
#' \item{fn}{The final functional value}
#' \item{itr}{The number of iterations}
#' \item{converge}{convergence code}
#' @references Zhou, W., Zhu, R. "A Parsimonious Personalized Dose Model vis Dimension Reduction." (2018)
#' \url{https://arxiv.org/abs/1802.06156}.
#' @references Wen, Z. and Yin, W., "A feasible method for optimization with orthogonality constraints." Mathematical Programming 142.1-2 (2013): 397-434.
#' DOI: \url{https://doi.org/10.1007/s10107-012-0584-1}


orthoDr_pm <- function(x, a, r, ndr = ndr, B.initial = NULL, bw = NULL,lambda = 0.1,
                       K = 20, method = c("direct_kernel","semi_svm"),
                       keep.data = FALSE, control = list(), maxitr = 500, verbose = FALSE, ncore = 0)
{
  if (!is.matrix(x)) stop("x must be a matrix")
  if (!is.numeric(x)) stop("x must be numerical")
  if (nrow(x) != length(r) | nrow(x) != length(a)) stop("Number of observations do not match")

  if (is.null(bw))
    bw = silverman(ndr, nrow(x))
  if (is.null(B.initial))
  {
    n= nrow(x)
    p = ncol(x)
    B.initial = P_SAVE(x, a, r, ndr = ndr, nslices0 =2)
  }else{
    if (!is.matrix(B.initial)) stop("B.initial must be a matrix")
    if (ncol(x) != nrow(B.initial) | ndr != ncol(B.initial)) stop("Dimention of B.initial is not correct")
  }

  # check tuning parameters
  control = control.check(control)

  # center matrix X, but do not scale

  B.initial = gramSchmidt(B.initial)$Q

  N = nrow(x)
  P = ncol(x)

  # standerdize
  X = x

  a_center = mean(a)
  a_scale = sd(a)
  aa = a/a_scale/bw

  if (method == "direct_kernel")
  {

    cdose= seq(min(a), max(a), length.out = K)

    cdose_scale = cdose/sd(cdose)/bw

    A.dist <- matrix(NA, nrow(x), K)
    for (k in 1:K)
    {
      A.dist[, k] = exp(-((aa - cdose_scale[k]))^2)
    }

    pre = Sys.time()
    fit = direct_pt_solver(B.initial, X, a, A.dist, cdose, r, lambda,bw,
                           control$rho, control$eta, control$gamma, control$tau, control$epsilon,
                           control$btol, control$ftol, control$gtol, maxitr, verbose, ncore)
    if (verbose > 0)
      cat(paste("Total time: ", round(as.numeric(Sys.time() - pre, units = "secs"), digits = 2), " secs\n", sep = ""))
  }

  if(method == "semi_svm")
  {

    pre = Sys.time()
    fit = semi_pt_solver(B.initial, X, r, a, bw,
                         control$rho, control$eta, control$gamma, control$tau, control$epsilon,
                         control$btol, control$ftol, control$gtol, maxitr, verbose,ncore)
    if (verbose > 0)
      cat(paste("Total time: ", round(as.numeric(Sys.time() - pre, units = "secs"), digits = 2), " secs\n", sep = ""))

  }

  fit$method = method
  fit$keep.data = keep.data

  if (keep.data)
  {
    fit[['x']] = x
    fit[['a']] = a
    fit[['r']] = r
    fit[['bw']] = bw
  }

  class(fit) <- c("orthoDr", "fit", "personalized_treatment", method)

  return(fit)
}

