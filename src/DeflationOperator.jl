import Base: push!

"""
DeflationOperator with structure
- power `p`
- dot function, this function has to be bilinear and symmetric for the linear solver
- shift
- roots
The deflation operator is is ``M(u) = \\frac{1}{\\prod_{i=1}^{n_{roots}}(shift + norm(u-roots_i)^p)}``
"""
struct DeflationOperator{T <: Real, vectype}
	power::T
	dot::Function
	shift::T
	roots::Vector{vectype}
end

push!(df::DeflationOperator{T, vectype}, v::vectype) where {T, vectype} = push!(df.roots, v)

function (df::DeflationOperator{T, vectype})(u::vectype) where {T, vectype}
	nrm  = u -> df.dot(u, u)
	@assert length(df.roots) > 0 "You need to specify some roots for deflation to work"
	# compute u - df.roots[1]
	tmp = copy(u);	axpy!(T(-1), df.roots[1], tmp)
	out = T(1) / nrm(tmp)^df.power + df.shift
	for ii = 2:length(df.roots)
		copyto!(tmp, u); axpy!(T(-1), df.roots[ii], tmp)
		out *= T(1) / nrm(tmp)^df.power + df.shift
	end
	return out
end

function scalardM(df::DeflationOperator{T, vectype}, u::vectype, du::vectype) where {T, vectype}
	# the deflation operator is Mu = 1/Π_i(shift + norm(u-ri)^p)
	# its differntial is -alpha(u, du) / Mu^2
	# the goal of this function is to compute alpha(u, du)
	@assert 1==0 "Not implemented"
	delta = T(1e-8)
	return (df(u + delta * du) - df(u))/delta

	# exact differentiation, not used
	# Mu = df(u)
	# p  = df.power
	# @assert length(df.roots) >0 "You need to specify some roots for deflation to work"
	# out = 0.0
	# for ii = 1:length(df.roots)
	# 	αi = 1 / (1 / nrm(u-df.roots[ii])^p + df.shift)
	# 	αi *= p / nrm(u-df.roots[ii])^(p+1)
	# 	out += αi * 2df.dot(u-df.roots[ii], du)
	# end
	# return out * Mu
end

struct DeflatedProblem{T, vectype, def <: DeflationOperator{T, vectype}}
	F::Function
	J::Function
	M::def
end

"""
Return the deflated function M(u) * F(u) where M(u) ∈ R
"""
function (df::DeflatedProblem{T, vectype, def})(u::vectype) where {T, vectype, def <: DeflationOperator{T, vectype}}
	out = df.F(u)
	rmul!(out, df.M(u))
	return out
end

###################################################################################################
# Linear operator
# function jac(df::DeflatedProblem, u)
#	 J = df.J(u)
# end

struct DeflatedLinearSolver <: LinearSolver end

"""
Implement the linear solver for the deflated problem
"""
function (dfl::DeflatedLinearSolver)(J, rhs)
	# the expression of the Functional is now
	# F(u) / Π_i(dot(u - root_i, u - root_i)^power + shift) := F(u) / M(u)
	# the expression of the differential is
	# dF(u)⋅du * M(u) + F(u) dM(u)⋅du

	# the point at which to compute the Jacobian
	u = J[1]
	# deflated Problem structure
	defPb = J[2]
	linsolve = J[3]
	Fu = defPb.F(u)
	Mu = defPb.M(u)

	# linear solve for the deflated problem. We note that Mu ∈ R
	# hence dM(u)⋅du is a scalar
	# M(u) * dF(u)⋅h + F(u) dM(u)⋅h = rhs
	h1, _, it1 = linsolve(defPb.J(u), rhs)
	h2, _, it2 = linsolve(defPb.J(u), Fu)

	# the expression of dM(u)⋅h
	# the solution is then h = Mu * h1 - z h2 where z has to be determined
	delta = 1e-8
	# z1 = (defPb.M(u + delta * h1) - Mu)/delta
	tmp = copy(u); axpy!(delta, h1, tmp)
	z1 = (defPb.M(tmp) - Mu) / delta

	# z2 = (defPb.M(u + delta * h2) - Mu)/delta
	copyto!(tmp, u); axpy!(delta, h2, tmp)
	z2 = (defPb.M(tmp) - Mu) / delta

	z = z1 / (Mu + z2)

	# return (h1 - z * h2) / Mu, true, (it1, it2)
	# @show h1 1/Mu
	copyto!(tmp, h1)
	axpy!(-z, h2, tmp)
	rmul!(tmp, 1 / Mu)
	return tmp, true, (it1, it2)
end