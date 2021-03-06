using Documenter, PseudoArcLengthContinuation

makedocs(doctest = false,
	sitename = "Pseudo Arc Length Continuation in Julia",
	format = Documenter.HTML(collapselevel = 1),
	# format = DocumenterLaTeX.LaTeX(),
	authors = "Romain Veltz",
	pages = Any[
		"Home" => "index.md",
		"Overview" => "guidelines.md",
		"Tutorials" => "tutorials.md",
		"Functionalities" => [
			"Plotting" => "plotting.md",
			"Linear / Eigen Solvers" => "linearsolver.md",
			"Bordered linear solvers" => "borderedlinearsolver.md",
			"Bifurcation detection" => "detectionBifurcation.md",
			"Fold / Hopf Continuation (codim 2)" => "codim2Continuation.md",
			"Normal form" =>[
				"Simple branch point" => "simplebp.md",
				"Non-simple branch point" => "nonsimplebp.md",
				"Simple Hopf point" => "simplehopf.md",
			],
			"Branch switching" => "branchswitching.md",
			"Deflated problem" => "deflatedproblem.md",
			"Constrained problem" => "constrainedproblem.md",
			"Periodic Orbits" => [
				"Introduction" => "periodicOrbit.md",
				"Finite Differences" => "periodicOrbitFD.md",
				"Shooting" => "periodicOrbitShooting.md",
				],
			"DiffEq wrapper" => "diffeq.md",
			"Bordered arrays" => "Borderedarrays.md",
			"Iterator Interface" => "iterator.md",
		],
		"Frequently Asked Questions" => "faq.md",
		"Library" => "library.md"
	]
	)

deploydocs(
	repo = "github.com/rveltz/PseudoArcLengthContinuation.jl.git",
)
