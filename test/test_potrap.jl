# using Revise
using Test, PseudoArcLengthContinuation, LinearAlgebra, Setfield, SparseArrays, ForwardDiff
const PALC = PseudoArcLengthContinuation

n = 250*150
M = 30
par = nothing
sol0 = rand(2n)				# 585.977 KiB
orbitguess_f = rand(2n*M+1)	# 17.166MiB
pb = PeriodicOrbitTrapProblem(
			(x, p) -> x.^2,
			(x, p) -> (dx -> 2 .* dx),
			rand(2n),
			rand(2n),
			M)

pbg = PeriodicOrbitTrapProblem(
			(x, p) -> x.^2,
			(x, p) -> (dx -> 2 .* dx),
			pb.ϕ,
			pb.xπ,
			M ; ongpu = true)

pbi = PeriodicOrbitTrapProblem(
			(o, x, p) -> o .= x.^2 ,
			((o, x, p, dx) -> o .= 2 .* dx),
			pb.ϕ,
			pb.xπ,
			M ; isinplace = true)
@test PALC.isInplace(pb) == false
# @time PALC.POTrapFunctional(pb, res, orbitguess_f)
# @time PALC.POTrapFunctional(pbi, res, orbitguess_f)
res = @time pb(orbitguess_f, par)
resg = @time pbg(orbitguess_f, par)
resi = @time pbi(orbitguess_f, par)
@test res == resi
@test res == resg

res = @time pb(orbitguess_f, par, orbitguess_f)
resg = @time pbg(orbitguess_f, par, orbitguess_f)
resi = @time pbi(orbitguess_f, par, orbitguess_f)
@test res == resi
@test res == resg

@time PALC.POTrapFunctional!(pbi, resi, orbitguess_f, par)
@time PALC.POTrapFunctionalJac!(pbi, resi, orbitguess_f, par, orbitguess_f)
@test res == resi

# @code_warntype PALC.POTrapFunctional!(pbi, resi, orbitguess_f)

# using BenchmarkTools
# @btime pb($orbitguess_f) 					# 13.535 ms (188 allocations: 34.34 MiB)
# @btime pbi($orbitguess_f) 					# 7.869 ms (128 allocations: 17.17 MiB)
# @btime pb($orbitguess_f, $orbitguess_f) 	# 25.500 ms (373 allocations: 51.51 MiB)
# @btime pbi($orbitguess_f, $orbitguess_f)  	# 12.595 ms (253 allocations: 17.18 MiB)
# @btime PALC.POTrapFunctional!($pbi, $resi, $orbitguess_f) # 7.104 ms (126 allocations: 5.88 KiB)
# @btime PALC.POTrapFunctionalJac!($pbi, $resi, $orbitguess_f, $orbitguess_f) # 10.528 ms (251 allocations: 11.69 KiB)
#
#
# using IterativeSolvers, LinearMaps
#
# Jmap = LinearMap{Float64}(dv -> pbi(orbitguess_f, dv), 2n*M+1 ; ismutating = false)
# gmres(Jmap, orbitguess_f; verbose = false, maxiter = 1)
# @time gmres(Jmap, orbitguess_f; verbose = false, maxiter = 10)
#
# Jmap! = LinearMap{Float64}((o, dv) -> PALC.POTrapFunctionalJac!(pbi, o, orbitguess_f, dv), 2n*M+1 ; ismutating = true)
# gmres(Jmap!, orbitguess_f; verbose = false, maxiter = 1)
# @time gmres(Jmap!, orbitguess_f; verbose = false, maxiter = 10)
#
# # @code_warntype PALC.POTrapFunctional!(pbi, resi, orbitguess_f)
# # @profiler PALC.POTrapFunctionalJac!(pbi, resi, orbitguess_f, orbitguess_f)
#
# Jmap2! = LinearMap{Float64}((o, dv) -> pbi(o, orbitguess_f, dv), 2n*M+1 ; ismutating = true)
# gmres(Jmap2!, orbitguess_f; verbose = false, maxiter = 1)
# @time gmres(Jmap2!, orbitguess_f; verbose = false, maxiter = 10)
#
# Jmap3! = LinearMap{Float64}((o, dv) -> (o .= pbi( orbitguess_f, dv)), 2n*M+1 ; ismutating = true)
# gmres(Jmap3!, orbitguess_f; verbose = false, maxiter = 1)
# @time gmres(Jmap3!, orbitguess_f; verbose = false, maxiter = 10)
#
# using ProfileView, Profile
# @profview gmres!(res, Jmap!, orbitguess_f; verbose = false, maxiter = 1)
# @profview gmres!(res, Jmap!, orbitguess_f; verbose = false, maxiter = 10)


####################################################################################################
# test whether we did not make any mistake in the improved version of the PO functional
function _functional(poPb, u0, p)
	M = poPb.M
	N = poPb.N
	T = u0[end]
	h = T / M

	u0c = reshape(u0[1:end-1], N, M)
	outc = similar(u0c)
	outc[:, 1] .= (u0c[:, 1] .- u0c[:, M-1]) .- h/2 .* (poPb.F(u0c[:, 1], p) .+ poPb.F(u0c[:, M-1], p))

	for ii = 2:M-1
		outc[:, ii] .= (u0c[:, ii] .- u0c[:, ii-1]) .- h/2 .* (poPb.F(u0c[:, ii], p) .+ poPb.F(u0c[:, ii-1], p))

	end

	# closure condition ensuring a periodic orbit
	outc[:, M] .= u0c[:, M] .- u0c[:, 1]

	return vcat(vec(outc),
			dot(u0c[:, 1] .- poPb.xπ, poPb.ϕ)) # this is the phase condition
end

function _dfunctional(poPb, u0, p, du)
	# jacobian of the functional

	M = poPb.M
	N = poPb.N
	T = u0[end]
	dT = du[end]
	h = T / M
	dh = dT / M

	u0c = reshape(u0[1:end-1], N, M)
	duc = reshape(du[1:end-1], N, M)
	outc = similar(u0c)

	outc[:, 1] .= (duc[:, 1] .- duc[:, M-1]) .- h/2 .* (poPb.J(u0c[:, 1], p)(duc[:, 1]) .+ poPb.J(u0c[:, M-1], p)(duc[:, M-1]))

	for ii = 2:M-1
		outc[:, ii] .= (duc[:, ii] .- duc[:, ii-1]) .- h/2 .* (poPb.J(u0c[:, ii], p)(duc[:, ii]) .+ poPb.J(u0c[:, ii-1], p)(duc[:, ii-1]))
	end

	outc[:, 1] .-=  dh/2 .* (poPb.F(u0c[:, 1], p) .+ poPb.F(u0c[:, M-1], p))
	for ii = 2:M-1
		outc[:, ii] .-= dh/2 .* (poPb.F(u0c[:, ii], p) .+ poPb.F(u0c[:, ii-1], p))
	end

	# closure condition ensuring a periodic orbit
	outc[:, M] .= duc[:, M] .- duc[:, 1]

	return vcat(vec(outc),
			dot(duc[:, 1], poPb.ϕ)) # this is the phase condition

end


res = @time pb(orbitguess_f, par)
_res = _functional(pb, orbitguess_f, par)
@test res ≈ _res

_du = rand(length(orbitguess_f))
res = @time pb(orbitguess_f, par, _du)
_res = _dfunctional(pb, orbitguess_f, par, _du)
@test res ≈ _res

####################################################################################################
# test whether the analytical version of the Jacobian is right
n = 50
pbsp = PeriodicOrbitTrapProblem(
			(x, p) -> cos.(x),
			(x, p) -> spdiagm(0 => -sin.(x)),
			rand(2n),
			rand(2n),
			10)
orbitguess_f = rand(2n*10+1)
dorbit = rand(2n*10+1)
Jfd = sparse( ForwardDiff.jacobian(x->pbsp(x, par), orbitguess_f) )
Jan = pbsp(Val(:JacFullSparse), orbitguess_f, par)
@test norm(Jfd - Jan, Inf) < 1e-6
####################################################################################################
# test whether the inplace version of computation of the Jacobian is right
n = 1000
pbsp = PeriodicOrbitTrapProblem(
			(x, p) -> x.^2,
			(x, p) -> spdiagm(0 => 2 .* x),
			rand(2n),
			rand(2n),
			M)

sol0 = rand(2n)
orbitguess_f = rand(2n*M+1)
Jpo = pbsp(Val(:JacFullSparse), orbitguess_f, par)
Jpo2 = copy(Jpo)
pbsp(Val(:JacFullSparseInplace), Jpo2, orbitguess_f, par)
@test nnz(Jpo2 - Jpo) == 0
####################################################################################################
# test of the version with inhomogenous time discretisation
pbsp = PeriodicOrbitTrapProblem(
			(x, p) -> cos.(x),
			(x, p) -> spdiagm(0 => -sin.(x)),
			rand(2n),
			rand(2n),
			10)

pbspti = PeriodicOrbitTrapProblem(
			(x, p) -> cos.(x),
			(x, p) -> spdiagm(0 => -sin.(x)),
			pbsp.ϕ,
			pbsp.xπ,
			ones(9) ./ 10)
PALC.getM(pbspti)
orbitguess_f = rand(2n*10+1)
@test pbspti.xπ ≈ pbsp.xπ
@test pbspti.ϕ ≈ pbsp.ϕ
pbspti(orbitguess_f, par)
@test pbsp(orbitguess_f, par) ≈ pbspti(orbitguess_f, par)
