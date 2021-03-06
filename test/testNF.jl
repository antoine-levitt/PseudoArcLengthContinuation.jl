# using Revise, Plots, Test
using PseudoArcLengthContinuation, LinearAlgebra, Setfield, SparseArrays, ForwardDiff, Parameters
const PALC = PseudoArcLengthContinuation
norminf = x -> norm(x, Inf)

function Fbp(x, p)
	return [x[1] * (3.23 .* p.μ - 0.12 * x[1] + 0.234 * x[1]^2) + x[2], x[2]]
end

par = (μ = -0.2, ν = 0)
####################################################################################################
opt_newton = PALC.NewtonPar(tol = 1e-8, verbose = false, maxIter = 20)
opts_br = ContinuationPar(dsmin = 0.001, dsmax = 0.05, ds = 0.01, pMax = 0.1, pMin = -0.3, detectBifurcation = 2, nev = 2, newtonOptions = opt_newton, maxSteps = 100)

	br, _ = @time PALC.continuation(
		Fbp, [0.1, 0.1], par, (@lens _.μ),
		printSolution = (x, p) -> norminf(x),
		opts_br; plot = false, verbosity = 0, normC = norminf)

####################################################################################################
# normal form computation
D(f, x, p, dx) = ForwardDiff.derivative(t->f(x .+ t .* dx, p), 0.)

d1F(x,p,dx1)         = D((z, p0) -> Fbp(z, p0), x, p, dx1)
d2F(x,p,dx1,dx2)     = D((z, p0) -> d1F(z, p0, dx1), x, p, dx2)
d3F(x,p,dx1,dx2,dx3) = D((z, p0) -> d2F(z, p0, dx1, dx2), x, p, dx3)
jet = (Fbp,
	(x, p) -> PALC.finiteDifferences(z -> Fbp(z, p), x),
	(x, p, dx1, dx2) -> d2F(x, p, dx1, dx2),
	(x, p, dx1, dx2, dx3) -> d3F(x, p, dx1, dx2, dx3))

bp = PALC.computeNormalForm(jet..., br, 1; verbose=true)

# normal form
nf = bp.nf

@test norm(nf[1]) < 1e-10
	@test norm(nf[2] - 3.23) < 1e-10
	@test norm(nf[3]/2 - -0.12) < 1e-10
	@test norm(nf[4]/6 - 0.234) < 1e-10

####################################################################################################
# Automatic branch switching
br, _ = continuation(jet..., br, 1, opts_br; verbosity = 0)

####################################################################################################
function Fbp2d(x, p)
	return [ x[1] * (3.23 .* p.μ - 0.123 * x[1]^2 - 0.234 * x[2]^2),
			 x[2] * (3.23 .* p.μ - 0.456 * x[1]^2 - 0.123 * x[2]^2),
			 x[3]]
end

d1F2d(x,p,dx1) = D((z, p0) -> Fbp2d(z, p0), x, p, dx1)
	d2F2d(x,p,dx1,dx2)     = D((z, p0) -> d1F2d(z, p0, dx1), x, p, dx2)
	d3F2d(x,p,dx1,dx2,dx3) = D((z, p0) -> d2F2d(z, p0, dx1, dx2), x, p, dx3)

jet = (Fbp2d, (x, p) -> ForwardDiff.jacobian(z -> Fbp2d(z, p), x), d2F2d, d3F2d)

par = (μ = -0.2, ν = 0)

br, _ = @time PALC.continuation(
	Fbp2d, [0.01, 0.01, 0.01], par, (@lens _.μ),
	printSolution = (x, p) -> norminf(x),
	setproperties(opts_br; nInversion = 2); plot = false, verbosity = 0, normC = norminf)

# we have to be careful to have the same basis as for Fbp2d or the NF will not match Fbp2d
bp2d = @time PALC.computeNormalForm(jet..., br, 1; ζs = [[1, 0, 0.], [0, 1, 0.]]);

PALC.nf(bp2d)
bp2d(rand(2), 0.2)
bp2d(Val(:reducedForm), rand(2), 0.2)

@test abs(bp2d.nf.b3[1,1,1,1] / 6 - -0.123) < 1e-10
@test abs(bp2d.nf.b3[1,1,2,2] / 2 - -0.234) < 1e-10
@test abs(bp2d.nf.b3[1,1,1,2] / 2 - -0.0)   < 1e-10
@test abs(bp2d.nf.b3[2,1,1,2] / 2 - -0.456) < 1e-10
@test norm(bp2d.nf.b2, Inf) < 3e-6
@test norm(bp2d.nf.b1 - 3.23 * I, Inf) < 1e-10
@test norm(bp2d.nf.a, Inf) < 1e-6
####################################################################################################
# test of the Hopf normal form
function Fsl2!(f, u, p, t)
	@unpack r, μ, ν, c3, c5 = p
	u1 = u[1]
	u2 = u[2]
	ua = u1^2 + u2^2

	f[1] = r * u1 - ν * u2 - ua * (c3 * u1 - μ * u2) - c5 * ua^2 * u1
	f[2] = r * u2 + ν * u1 - ua * (c3 * u2 + μ * u1) - c5 * ua^2 * u2

	return f
end

Fsl2(x, p) = Fsl2!(similar(x), x, p, 0.)
par_sl = (r = 0.5, μ = 0.132, ν = 1.0, c3 = 1.123, c5 = 0.2)

d1Fsl(x,p,dx1)         = D((z, p0) -> Fsl2(z, p0), x, p, dx1)
d2Fsl(x,p,dx1,dx2)     = D((z, p0) -> d1Fsl(z, p0, dx1), x, p, dx2)
d3Fsl(x,p,dx1,dx2,dx3) = D((z, p0) -> d2Fsl(z, p0, dx1, dx2), x, p, dx3)

# detect hopf bifurcation
opts_br = ContinuationPar(dsmin = 0.001, dsmax = 0.02, ds = 0.01, pMax = 0.1, pMin = -0.3, detectBifurcation = 2, nev = 2, newtonOptions = (@set opt_newton.verbose = true), maxSteps = 100)

br, _ = @time PALC.continuation(
	Fsl2, [0.0, 0.0], (@set par_sl.r = -0.1), (@lens _.r),
	printSolution = (x, p) -> norminf(x),
	opts_br; plot = false, verbosity = 3, normC = norminf)

hp = PALC.computeNormalForm(
	(x, p) -> Fsl2(x, p),
	(x, p) -> ForwardDiff.jacobian(z -> Fsl2(z, p), x),
	(x, p, dx1, dx2) -> 	 d2Fsl(x, p, dx1, dx2),
	(x, p, dx1, dx2, dx3) -> d3Fsl(x, p, dx1, dx2, dx3),
	br, 1)

nf = hp.nf

@test abs(nf.a - 1) < 1e-10
@test abs(nf.b/2 - (-par_sl.c3 + im*par_sl.μ)) < 1e-10
