using Revise
	using DiffEqOperators, ForwardDiff, DifferentialEquations
	using PseudoArcLengthContinuation, LinearAlgebra, Plots, SparseArrays, Parameters, Setfield
	const PALC = PseudoArcLengthContinuation

norminf = x -> norm(x, Inf)

function Laplacian2D(Nx, Ny, lx, ly, bc = :Dirichlet)
	hx = 2lx/Nx
	hy = 2ly/Ny
	D2x = CenteredDifference(2, 2, hx, Nx)
	D2y = CenteredDifference(2, 2, hy, Ny)
	if bc == :Neumann
		Qx = Neumann0BC(hx)
		Qy = Neumann0BC(hy)
	elseif  bc == :Dirichlet
		Qx = Dirichlet0BC(typeof(hx))
		Qy = Dirichlet0BC(typeof(hy))
	end
	D2xsp = sparse(D2x * Qx)[1]
	D2ysp = sparse(D2y * Qy)[1]

	A = kron(sparse(I, Ny, Ny), D2xsp) + kron(D2ysp, sparse(I, Nx, Nx))
	return A, D2x
end

function NL!(f, u, p, t = 0.)
	@unpack r, μ, ν, c3, c5 = p
	n = div(length(u), 2)
	u1 = @view u[1:n]
	u2 = @view u[n+1:2n]

	ua = u1.^2 .+ u2.^2

	f1 = @view f[1:n]
	f2 = @view f[n+1:2n]

	@. f1 .= r * u1 - ν * u2 - ua * (c3 * u1 - μ * u2) - c5 * ua^2 * u1
	@. f2 .= r * u2 + ν * u1 - ua * (c3 * u2 + μ * u1) - c5 * ua^2 * u2

	return f
end

function NL(u, p)
	out = similar(u)
	NL!(out, u, p)
end

function Fcgl!(f, u, p, t = 0.)
	mul!(f, p.Δ, u)
	f .= f .+ NL(u, p)
end

Fcgl(u, p, t = 0.) = Fcgl!(similar(u), u, p, t)

# computation of the first derivative
# d1Fcgl(x, p, dx) = ForwardDiff.derivative(t -> Fcgl(x .+ t .* dx, p), 0.)

d1NL(x, p, dx) = ForwardDiff.derivative(t -> NL(x .+ t .* dx, p), 0.)

function dFcgl(x, p, dx)
	f = similar(dx)
	mul!(f, p.Δ, dx)

	nl = d1NL(x, p, dx)
	f .= f .+ nl
end

function Jcgl(u, p, t = 0.)
	@unpack r, μ, ν, c3, c5, Δ = p

	n = div(length(u), 2)
	u1 = @view u[1:n]
	u2 = @view u[n+1:2n]

	ua = u1.^2 .+ u2.^2

	f1u = zero(u1)
	f2u = zero(u1)
	f1v = zero(u1)
	f2v = zero(u1)

	@. f1u =  r - 2 * u1 * (c3 * u1 - μ * u2) - c3 * ua - 4 * c5 * ua * u1^2 - c5 * ua^2
	@. f1v = -ν - 2 * u2 * (c3 * u1 - μ * u2)  + μ * ua - 4 * c5 * ua * u1 * u2
	@. f2u =  ν - 2 * u1 * (c3 * u2 + μ * u1)  - μ * ua - 4 * c5 * ua * u1 * u2
	@. f2v =  r - 2 * u2 * (c3 * u2 + μ * u1) - c3 * ua - 4 * c5 * ua * u2 ^2 - c5 * ua^2

	jacdiag = vcat(f1u, f2v)

	Δ + spdiagm(0 => jacdiag, n => f1v, -n => f2u)
end

####################################################################################################
Nx = 41*1
	Ny = 21*1
	n = Nx*Ny
	lx = pi
	ly = pi/2

	Δ = Laplacian2D(Nx, Ny, lx, ly)[1]
	par_cgl = (r = 0.5, μ = 0.1, ν = 1.0, c3 = -1.0, c5 = 1.0, Δ = blockdiag(Δ, Δ))
	sol0 = 0.1rand(2Nx, Ny)
	sol0_f = vec(sol0)

####################################################################################################
eigls = EigArpack(1.0, :LM)
# eigls = eig_MF_KrylovKit(tol = 1e-8, dim = 60, x₀ = rand(ComplexF64, Nx*Ny), verbose = 1)
opt_newton = PALC.NewtonPar(tol = 1e-9, verbose = true, eigsolver = eigls, maxIter = 20)
opts_br = ContinuationPar(dsmax = 0.02, ds = 0.01, pMax = 2., detectBifurcation = 2, nev = 15, newtonOptions = (@set opt_newton.verbose = false), nInversion = 4)

	br, u1 = @time PALC.continuation(Fcgl, Jcgl, vec(sol0), par_cgl, (@lens _.r), opts_br, verbosity = 0)

plot(br)
####################################################################################################
# Look for periodic orbits
f1 = DiffEqArrayOperator(par_cgl.Δ)
f2 = NL!
prob_sp = SplitODEProblem(f1, f2, sol0_f, (0.0, 120.0), @set par_cgl.r = 1.2; atol = 1e-14, rtol = 1e-14, dt = 0.1)
prob = ODEProblem(Fcgl, sol0_f, (0.0, 120.0), @set par_cgl.r = 1.2)#; jac = Jbr, jac_prototype = Jbr(sol0_f, par_cgl))
####################################################################################################
# sol = @time solve(prob, Vern9(); abstol=1e-14, reltol=1e-14)
sol = @time solve(prob_sp, ETDRK2(krylov=true); abstol=1e-14, reltol=1e-14, dt = 0.1) #1.78s
# sol = @time solve(prob, LawsonEuler(krylov=true, m=50); abstol=1e-14, reltol=1e-14, dt = 0.1)
# sol = @time solve(prob_sp, CNAB2(linsolve=LinSolveGMRES()); abstol=1e-14, reltol=1e-14, dt = 0.03)

plot(sol.t, [norm(v[1:Nx*Ny], Inf) for v in sol.u],xlims=(115,120))

# plotting the solution as a movie
for ii = 1:20:length(sol.t)
	# heatmap(reshape(sol[1:Nx*Ny,ii],Nx,Ny),title="$(sol.t[ii])") |> display
end

####################################################################################################
# this encodes the functional for the Shooting problem
probSh = ShootingProblem(
	# pass the vector field and parameter (to be passed to the vector field)
	Fcgl, par_cgl,

	# we pass the ODEProblem encoding the flow and the time stepper
	prob_sp, ETDRK2(krylov = true),

	[sol[:, end]])

initpo = vcat(sol(116.), 4.9) |> vec
	probSh(initpo, @set par_cgl.r = 1.2) |> norminf

ls = GMRESIterativeSolvers(tol = 1e-4, N = 2Nx * Ny + 1, maxiter = 50, verbose = false)
	optn = NewtonPar(verbose = true, tol = 1e-9,  maxIter = 25, linsolver = ls)
outpo, _ = @time newton(
		probSh, initpo, (@set par_cgl.r = 1.2), optn; normN = norminf,
		# callback = (x, f, J, res, iteration, options; kwargs...) -> (println("--> T = ",x[end]);x[end] = max(0.1,x[end]);x[end] = min(30.1,x[end]);true)
		)
outpo[end]
heatmap(reshape(outpo[1:Nx*Ny], Nx, Ny), color = :viridis)

eig = EigKrylovKit(tol = 1e-7, x₀ = rand(2Nx*Ny), verbose = 2, dim = 40)
	opts_po_cont = ContinuationPar(dsmin = 0.001, dsmax = 0.02, ds= -0.01, pMax = 2.5, maxSteps = 32, newtonOptions = (@set optn.eigsolver = eig), nev = 15, precisionStability = 1e-3, detectBifurcation = 0, plotEveryNsteps = 1)
br_po, upo , _= @time continuation(probSh, outpo, (@set par_cgl.r = 1.2), (@lens _.r),
		opts_po_cont;
		verbosity = 3,
		plot = true,
		# callbackN = cb_ss,
		plotSolution = (x, p; kwargs...) -> heatmap!(reshape(x[1:Nx*Ny], Nx, Ny); color=:viridis, kwargs...),
		printSolution = (u, p) -> PALC.getAmplitude(probSh, u, (@set par_cgl.r = p); ratio = 2), normC = norminf)

####################################################################################################
# automatic branch switching
using ForwardDiff
function D(f, x, p, dx)
	return ForwardDiff.derivative(t->f(x .+ t .* dx, p), 0.)
end
d1Fcgl(x,p,dx1) = D((z, p0) -> Fcgl(z, p0), x, p, dx1)
	d2Fcgl(x,p,dx1,dx2) = D((z, p0) -> d1Fcgl(z, p0, dx1), x, p, dx2)
	d3Fcgl(x,p,dx1,dx2,dx3) = D((z, p0) -> d2Fcgl(z, p0, dx1, dx2), x, p, dx3)

jet = (Fcgl, Jcgl, d2Fcgl, d3Fcgl)

ls = GMRESIterativeSolvers(tol = 1e-4, maxiter = 50, verbose = false)
	optn = NewtonPar(verbose = true, tol = 1e-9,  maxIter = 25, linsolver = ls)
eig = EigKrylovKit(tol = 1e-7, x₀ = rand(2Nx*Ny), verbose = 2, dim = 40)
	opts_po_cont = ContinuationPar(dsmin = 0.001, dsmax = 0.02, ds= 0.01, pMax = 2.5, maxSteps = 32, newtonOptions = (@set optn.eigsolver = eig), nev = 15, precisionStability = 1e-3, detectBifurcation = 0, plotEveryNsteps = 1)

br_po, _ = continuation(
	jet...,	br, 2,
	# arguments for continuation
	opts_po_cont,
	# probSh;
	ShootingProblem(1, par_cgl, prob_sp, ETDRK2(krylov = true)) ;
	verbosity = 3, plot = true, ampfactor = 1.5, δp = 0.01,
	# callbackN = (x, f, J, res, iteration, itl, options; kwargs...) -> (println("--> amplitude = ", PALC.amplitude(x, n, M; ratio = 2));true),
	finaliseSolution = (z, tau, step, contResult) ->
		(Base.display(contResult.eig[end].eigenvals) ;true),
	printSolution = (u, p) -> PALC.getAmplitude(probSh, u, (@set par_cgl.r = p); ratio = 2),
	normC = norminf)

#ShootingProblem(1, par_cgl, prob_sp, ETDRK2(krylov = true)) ;
