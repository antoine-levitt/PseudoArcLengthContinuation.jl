using Test, PseudoArcLengthContinuation, LinearAlgebra, SparseArrays, Arpack

# test the type BorderedVector
z_pred = PseudoArcLengthContinuation.BorderedVector(rand(10),1.0)
tau_pred = PseudoArcLengthContinuation.BorderedVector(rand(10),2.0)
z_pred = z_pred + 2tau_pred

# test the linear solver LinearBorderSolver
println("--> Test linear Bordered solver")
J0 = rand(10,10) * 0.1 + I
rhs = rand(10)
sol_explicit = J0 \ rhs
sol_bd1, sol_bd2, _ = PseudoArcLengthContinuation.linearBorderedSolver(J0[1:end-1,1:end-1], J0[1:end-1,end], J0[end,1:end-1], J0[end,end], rhs[1:end-1], rhs[end], Default())

@test norm(sol_explicit[1:end-1] - sol_bd1, Inf64) < 1e-12
@test norm(sol_explicit[end] - sol_bd2, Inf64) < 1e-12

# test the linear solvers for matrix free formulations
J0 = I + sprand(100,100,0.1)
Jmf = x -> J0*x
x0 = rand(100)
ls = Default()
out = ls(J0, x0)

ls = GMRES_KrylovKit{Float64}(rtol = 1e-9, dim = 100)
outkk = ls(J0, x0)
@test norm(out[1] - outkk[1], Inf64) < 1e-7
outkk = ls(Jmf, x0)
@test norm(out[1] - outkk[1], Inf64) < 1e-7


ls = GMRES_IterativeSolvers{Float64}(N = 100, tol = 1e-9)
outit = ls(J0, x0)
@test norm(out[1] - outit[1], Inf64) < 1e-7


# test the eigen solvers for matrix free formulations
out = Arpack.eigs(J0, nev = 20, which = :LR)

eil = PseudoArcLengthContinuation.eig_KrylovKit(tol = 1e-6)
outkk = eil(J0, 20)
eil = PseudoArcLengthContinuation.eig_MF_KrylovKit(tol = 1e-6, x₀ = x0)
outkkmf = eil(Jmf, 20)

@test norm(out[1] - outkk[1][1:20]) < 1e-6
@test norm(out[1] - outkkmf[1][1:20]) < 1e-6
