# Copyright (c) 2025: Joaquim Garcia, Oscar Dowson and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

"""
    Analyzer() <: ModelAnalyzer.AbstractAnalyzer

The `Analyzer` type is used to perform infeasibility analysis on a model.

## Example
```julia
julia> data = ModelAnalyzer.analyze(
    Analyzer(),
    model,
    optimizer = nothing,,
)
```

The additional keyword argument `optimizer` is used to specify the optimizer to
use for the IIS resolver.
"""
struct Analyzer <: ModelAnalyzer.AbstractAnalyzer end

"""
    AbstractInfeasibilitylIssue

Abstract type for infeasibility issues found during the analysis of a
model.
"""
abstract type AbstractInfeasibilitylIssue <: ModelAnalyzer.AbstractIssue end

"""
    InfeasibleBounds{T} <: AbstractInfeasibilitylIssue

The `InfeasibleBounds` issue is identified when a variable has a lower bound
that is greater than its upper bound.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Infeasibility.InfeasibleBounds)
````
"""
struct InfeasibleBounds{T} <: AbstractInfeasibilitylIssue
    variable::MOI.VariableIndex
    lb::T
    ub::T
end

ModelAnalyzer.variable(issue::InfeasibleBounds) = issue.variable

ModelAnalyzer.values(issue::InfeasibleBounds) = [issue.lb, issue.ub]

"""
    InfeasibleIntegrality{T} <: AbstractInfeasibilitylIssue

The `InfeasibleIntegrality` issue is identified when a variable has an
integrality constraint (like `MOI.Integer` or `MOI.ZeroOne`) that is not
consistent with its bounds. That is, the bounds do not allow for any
integer value to be feasible.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(
    ModelAnalyzer.Infeasibility.InfeasibleIntegrality
)
```
"""
struct InfeasibleIntegrality{T} <: AbstractInfeasibilitylIssue
    variable::MOI.VariableIndex
    lb::T
    ub::T
    set::Union{MOI.Integer,MOI.ZeroOne}#, MOI.Semicontinuous{T}, MOI.Semiinteger{T}}
end

ModelAnalyzer.variable(issue::InfeasibleIntegrality) = issue.variable

ModelAnalyzer.values(issue::InfeasibleIntegrality) = [issue.lb, issue.ub]

ModelAnalyzer.set(issue::InfeasibleIntegrality) = issue.set

"""
    InfeasibleConstraintRange{T} <: AbstractInfeasibilitylIssue

The `InfeasibleConstraintRange` issue is identified when a constraint cannot
be satisfied given the variable bounds. This analysis only considers one
constraint at a time and all variable bounds of variables involved in the
constraint.
This issue can only be found is all variable bounds are consistent, that is,
no issues of type `InfeasibleBounds` were found in the first layer of analysis.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(
    ModelAnalyzer.Infeasibility.InfeasibleConstraintRange
)
```
"""
struct InfeasibleConstraintRange{T} <: AbstractInfeasibilitylIssue
    constraint::MOI.ConstraintIndex
    lb::T
    ub::T
    set::Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T}}
end

ModelAnalyzer.constraint(issue::InfeasibleConstraintRange) = issue.constraint

ModelAnalyzer.values(issue::InfeasibleConstraintRange) = [issue.lb, issue.ub]

ModelAnalyzer.set(issue::InfeasibleConstraintRange) = issue.set

"""
    IrreducibleInfeasibleSubset <: AbstractInfeasibilitylIssue

The `IrreducibleInfeasibleSubset` issue is identified when a subset of
constraints cannot be satisfied simultaneously. This is typically found
by the IIS resolver after the first two layers of infeasibility analysis
have been completed with no issues, that is, no issues of any other type
were found.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(
    ModelAnalyzer.Infeasibility.IrreducibleInfeasibleSubset
)
```
"""
struct IrreducibleInfeasibleSubset <: AbstractInfeasibilitylIssue
    constraint::Vector{<:MOI.ConstraintIndex}
end

ModelAnalyzer.constraints(issue::IrreducibleInfeasibleSubset) = issue.constraint

"""
    Data <: ModelAnalyzer.AbstractData

The `Data` type is used to store the results of the infeasibility analysis.
This type contains vectors of the various infeasibility issues found during
the analysis, including `InfeasibleBounds`, `InfeasibleIntegrality`,
`InfeasibleConstraintRange`, and `IrreducibleInfeasibleSubset`.
"""
Base.@kwdef mutable struct Data <: ModelAnalyzer.AbstractData
    infeasible_bounds::Vector{InfeasibleBounds} = InfeasibleBounds[]
    infeasible_integrality::Vector{InfeasibleIntegrality} =
        InfeasibleIntegrality[]

    constraint_range::Vector{InfeasibleConstraintRange} =
        InfeasibleConstraintRange[]

    iis::Vector{IrreducibleInfeasibleSubset} = IrreducibleInfeasibleSubset[]
end
