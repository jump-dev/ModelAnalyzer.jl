# Copyright (c) 2025: Joaquim Garcia, Oscar Dowson and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# TODO
# 1 - JuMP: primal_feasibility_report should have a typed error for not found stuff so we can capture
# 2 - Dualization: should consider and option to dont treat @variable(m, x >= 0) differently from @variable(m, x >= 1)
# 3 - Dualization: JuMP model dualization should hold the primal dual map, maybe a JuMP converted version
# 4 - Dualization: Primal dual map could work with a getindex for simpler usage

module Feasibility

import ModelAnalyzer
import Dualization
import JuMP
import JuMP.MOI as MOI
import Printf

"""
    Analyzer() <: ModelAnalyzer.AbstractAnalyzer

The `Analyzer` type is used to perform feasibility analysis on a JuMP model.

## Example

```julia
julia> data = ModelAnalyzer.analyze(
    ModelAnalyzer.Feasibility.Analyzer(),
    model;
    primal_point::Union{Nothing, Dict} = nothing,
    dual_point::Union{Nothing, Dict} = nothing,
    atol::Float64 = 1e-6,
    skip_missing::Bool = false,
    dual_check = true,
);
```

The additional parameters:
- `primal_point`: The primal solution point to use for feasibility checking.
  If `nothing`, it will use the current primal solution from optimized model.
- `dual_point`: The dual solution point to use for feasibility checking.
  If `nothing` and the model can be dualized, it will use the current dual
  solution from the model.
- `atol`: The absolute tolerance for feasibility checking.
- `skip_missing`: If `true`, constraints with missing variables in the provided
  point will be ignored.
- `dual_check`: If `true`, it will perform dual feasibility checking. Disabling
  the dual check will also disable complementarity checking.
"""
struct Analyzer <: ModelAnalyzer.AbstractAnalyzer end

"""
    AbstractFeasibilityIssue <: AbstractNumericalIssue

Abstract type for feasibility issues found during the analysis of a JuMP model.
"""
abstract type AbstractFeasibilityIssue <: ModelAnalyzer.AbstractIssue end

"""
    PrimalViolation <: AbstractFeasibilityIssue

The `PrimalViolation` issue is identified when a primal constraint has a
left-hand-side value that is not within the constraint's set.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.PrimalViolation)
```
"""
struct PrimalViolation <: AbstractFeasibilityIssue
    ref::JuMP.ConstraintRef
    violation::Float64
end

"""
    DualViolation <: AbstractFeasibilityIssue

The `DualViolation` issue is identified when a constraint has a dual value
that is not within the dual constraint's set.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.DualViolation)
```
"""
struct DualViolation <: AbstractFeasibilityIssue
    ref::Union{JuMP.ConstraintRef,JuMP.VariableRef}
    violation::Float64
end

"""
    ComplemetarityViolation <: AbstractFeasibilityIssue

The `ComplemetarityViolation` issue is identified when a pair of primal
constraint and dual variable has a nonzero complementarity value, i.e., the
inner product of the primal constraint's slack and the dual variable's
violation is not zero.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.ComplemetarityViolation)
```
"""
struct ComplemetarityViolation <: AbstractFeasibilityIssue
    ref::JuMP.ConstraintRef
    violation::Float64
end

"""
    DualObjectiveMismatch <: AbstractFeasibilityIssue

The `DualObjectiveMismatch` issue is identified when the dual objective value
computed from problem data and the dual solution does not match the solver's
dual objective value.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.DualObjectiveMismatch)
```
"""
struct DualObjectiveMismatch <: AbstractFeasibilityIssue
    obj::Float64
    obj_solver::Float64
end

"""
    PrimalObjectiveMismatch <: AbstractFeasibilityIssue

The `PrimalObjectiveMismatch` issue is identified when the primal objective
value computed from problem data and the primal solution does not match
the solver's primal objective value.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.PrimalObjectiveMismatch)
```
"""
struct PrimalObjectiveMismatch <: AbstractFeasibilityIssue
    obj::Float64
    obj_solver::Float64
end

"""
    PrimalDualMismatch <: AbstractFeasibilityIssue

The `PrimalDualMismatch` issue is identified when the primal objective value
computed from problem data and the primal solution does not match the dual
objective value computed from problem data and the dual solution.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.PrimalDualMismatch)
```
"""
struct PrimalDualMismatch <: AbstractFeasibilityIssue
    primal::Float64
    dual::Float64
end

"""
    PrimalDualSolverMismatch <: AbstractFeasibilityIssue

The `PrimalDualSolverMismatch` issue is identified when the primal objective
value reported by the solver does not match the dual objective value reported
by the solver.

For more information, run:
```julia
julia> ModelAnalyzer.summarize(ModelAnalyzer.Feasibility.PrimalDualSolverMismatch)
```
"""
struct PrimalDualSolverMismatch <: AbstractFeasibilityIssue
    primal::Float64
    dual::Float64
end

"""
    Data

The `Data` structure holds the results of the feasibility analysis performed
by the `ModelAnalyzer.analyze` function for a JuMP model. It contains
the configuration used for the analysis, the primal and dual points, and
the lists of various feasibility issues found during the analysis.
"""
Base.@kwdef mutable struct Data <: ModelAnalyzer.AbstractData
    # analysis configuration
    primal_point::Union{Nothing,AbstractDict}
    dual_point::Union{Nothing,AbstractDict}
    atol::Float64
    skip_missing::Bool
    dual_check::Bool
    # analysis results
    primal::Vector{PrimalViolation} = PrimalViolation[]
    dual::Vector{DualViolation} = DualViolation[]
    complementarity::Vector{ComplemetarityViolation} = ComplemetarityViolation[]
    # objective analysis
    dual_objective_mismatch::Vector{DualObjectiveMismatch} =
        DualObjectiveMismatch[]
    primal_objective_mismatch::Vector{PrimalObjectiveMismatch} =
        PrimalObjectiveMismatch[]
    primal_dual_mismatch::Vector{PrimalDualMismatch} = PrimalDualMismatch[]
    primal_dual_solver_mismatch::Vector{PrimalDualSolverMismatch} =
        PrimalDualSolverMismatch[]
end

function ModelAnalyzer._summarize(io::IO, ::Type{PrimalViolation})
    return print(io, "# PrimalViolation")
end

function ModelAnalyzer._summarize(io::IO, ::Type{DualViolation})
    return print(io, "# DualViolation")
end

function ModelAnalyzer._summarize(io::IO, ::Type{ComplemetarityViolation})
    return print(io, "# ComplemetarityViolation")
end

function ModelAnalyzer._summarize(io::IO, ::Type{DualObjectiveMismatch})
    return print(io, "# DualObjectiveMismatch")
end

function ModelAnalyzer._summarize(io::IO, ::Type{PrimalObjectiveMismatch})
    return print(io, "# PrimalObjectiveMismatch")
end

function ModelAnalyzer._summarize(io::IO, ::Type{PrimalDualMismatch})
    return print(io, "# PrimalDualMismatch")
end

function ModelAnalyzer._summarize(io::IO, ::Type{PrimalDualSolverMismatch})
    return print(io, "# PrimalDualSolverMismatch")
end

function ModelAnalyzer._verbose_summarize(io::IO, ::Type{PrimalViolation})
    return print(
        io,
        """
        # PrimalViolation

        ## What

        A `PrimalViolation` issue is identified when a constraint has 
        function , i.e., a left-hand-side value, that is not within
        the constraint's set.

        ## Why

        This can happen due to a few reasons:
        - The solver did not converge.
        - The model is infeasible and the solver converged to an
          infeasible point.
        - The solver converged to a low accuracy solution, which might
          happen due to transformations in the the model presolve or
          due to numerical issues.

        ## How to fix

        Check the solver convergence log and the solver status. If the
        solver did not converge, you might want to try alternative
        solvers or adjust the solver options. If the solver converged
        to an infeasible point, you might want to check the model
        constraints and bounds. If the solver converged to a low
        accuracy solution, you might want to adjust the solver options
        or the model presolve.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, ::Type{DualViolation})
    return print(
        io,
        """
        # DualViolation

        ## What

        A `DualViolation` issue is identified when a constraint has
        a dual value that is not within the dual constraint's set.

        ## Why

        This can happen due to a few reasons:
        - The solver did not converge.
        - The model is infeasible and the solver converged to an
          infeasible point.
        - The solver converged to a low accuracy solution, which might
          happen due to transformations in the the model presolve or
          due to numerical issues.

        ## How to fix

        Check the solver convergence log and the solver status. If the
        solver did not converge, you might want to try alternative
        solvers or adjust the solver options. If the solver converged
        to an infeasible point, you might want to check the model
        constraints and bounds. If the solver converged to a low
        accuracy solution, you might want to adjust the solver options
        or the model presolve.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    ::Type{ComplemetarityViolation},
)
    return print(
        io,
        """
        # ComplemetarityViolation

        ## What

        A `ComplemetarityViolation` issue is identified when a pair of
        primal constraint and dual varaible has a nonzero
        complementarity value, i.e., the inner product of the primal
        constraint's slack and the dual variable's violation is
        not zero.

        ## Why

        This can happen due to a few reasons:
        - The solver did not converge.
        - The model is infeasible and the solver converged to an
          infeasible point.
        - The solver converged to a low accuracy solution, which might
          happen due to transformations in the the model presolve or
          due to numerical issues.

        ## How to fix

        Check the solver convergence log and the solver status. If the
        solver did not converge, you might want to try alternative
        solvers or adjust the solver options. If the solver converged
        to an infeasible point, you might want to check the model
        constraints and bounds. If the solver converged to a low
        accuracy solution, you might want to adjust the solver options
        or the model presolve.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, ::Type{DualObjectiveMismatch})
    return print(
        io,
        """
        # DualObjectiveMismatch

        ## What

        A `DualObjectiveMismatch` issue is identified when the dual
        objective value computed from problema data and the dual
        solution does not match the solver's dual objective
        value.

        ## Why

        This can happen due to:
        - The solver performed presolve transformations and the
          reported dual objective is reported from the transformed
          problem.
        - Bad problem numerical conditioning, very large and very
          small coefficients might be present in the model.

        ## How to fix

        Check the solver convergence log and the solver status.
        Consider reviewing the coefficients of the objective function.
        Consider reviewing the options set in the solver.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    ::Type{PrimalObjectiveMismatch},
)
    return print(
        io,
        """
        # PrimalObjectiveMismatch

        ## What

        A `PrimalObjectiveMismatch` issue is identified when the primal
        objective value computed from problema data and the primal
        solution does not match the solver's primal objective
        value.

        ## Why

        This can happen due to:
        - The solver performed presolve transformations and the
          reported primal objective is reported from the transformed
          problem.
        - Bad problem numerical conditioning, very large and very
          small coefficients might be present in the model.

        ## How to fix

        Check the solver convergence log and the solver status.
        Consider reviewing the coefficients of the objective function.
        Consider reviewing the options set in the solver.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, ::Type{PrimalDualMismatch})
    return print(
        io,
        """
        # PrimalDualMismatch

        ## What

        A `PrimalDualMismatch` issue is identified when the primal
        objective value computed from problema data and the primal
        solution does not match the dual objective value computed
        from problem data and the dual solution.

        ## Why

        This can happen due to:
        - The solver did not converge.
        - Bad problem numerical conditioning, very large and very
          small coefficients might be present in the model.

        ## How to fix

        Check the solver convergence log and the solver status.
        Consider reviewing the coefficients of the model.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    ::Type{PrimalDualSolverMismatch},
)
    return print(
        io,
        """
        # PrimalDualSolverMismatch

        ## What

        A `PrimalDualSolverMismatch` issue is identified when the primal
        objective value reported by the solver does not match the dual
        objective value reported by the solver.

        ## Why

        This can happen due to:
        - The solver did not converge.

        ## How to fix

        Check the solver convergence log and the solver status.

        ## More information

        No extra information for this issue.
        """,
    )
end

function ModelAnalyzer._summarize(io::IO, issue::PrimalViolation)
    return print(io, _name(issue.ref), " : ", issue.violation)
end

function ModelAnalyzer._summarize(io::IO, issue::DualViolation)
    return print(io, _name(issue.ref), " : ", issue.violation)
end

function ModelAnalyzer._summarize(io::IO, issue::ComplemetarityViolation)
    return print(io, _name(issue.ref), " : ", issue.violation)
end

function ModelAnalyzer._summarize(io::IO, issue::DualObjectiveMismatch)
    return ModelAnalyzer._verbose_summarize(io, issue)
end

function ModelAnalyzer._summarize(io::IO, issue::PrimalObjectiveMismatch)
    return ModelAnalyzer._verbose_summarize(io, issue)
end

function ModelAnalyzer._summarize(io::IO, issue::PrimalDualMismatch)
    return ModelAnalyzer._verbose_summarize(io, issue)
end

function ModelAnalyzer._summarize(io::IO, issue::PrimalDualSolverMismatch)
    return ModelAnalyzer._verbose_summarize(io, issue)
end

function ModelAnalyzer._verbose_summarize(io::IO, issue::PrimalViolation)
    return print(
        io,
        "Constraint ",
        _name(issue.ref),
        " has violation ",
        issue.violation,
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, issue::DualViolation)
    if issue.ref isa JuMP.ConstraintRef
        return print(
            io,
            "Constraint ",
            _name(issue.ref),
            " has violation ",
            issue.violation,
        )
    else
        return print(
            io,
            "Variable ",
            _name(issue.ref),
            " has violation ",
            issue.violation,
        )
    end
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    issue::ComplemetarityViolation,
)
    return print(
        io,
        "Constraint ",
        _name(issue.ref),
        " has violation ",
        issue.violation,
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, issue::DualObjectiveMismatch)
    return print(
        io,
        "Dual objective mismatch: ",
        issue.obj,
        " (computed) vs ",
        issue.obj_solver,
        " (reported by solver)\n",
    )
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    issue::PrimalObjectiveMismatch,
)
    return print(
        io,
        "Primal objective mismatch: ",
        issue.obj,
        " (computed) vs ",
        issue.obj_solver,
        " (reported by solver)\n",
    )
end

function ModelAnalyzer._verbose_summarize(io::IO, issue::PrimalDualMismatch)
    return print(
        io,
        "Primal dual mismatch: ",
        issue.primal,
        " (computed primal) vs ",
        issue.dual,
        " (computed dual)\n",
    )
end

function ModelAnalyzer._verbose_summarize(
    io::IO,
    issue::PrimalDualSolverMismatch,
)
    return print(
        io,
        "Solver reported objective mismatch: ",
        issue.primal,
        " (reported primal) vs ",
        issue.dual,
        " (reported dual)\n",
    )
end

function ModelAnalyzer.list_of_issues(data::Data, ::Type{PrimalViolation})
    return data.primal
end

function ModelAnalyzer.list_of_issues(data::Data, ::Type{DualViolation})
    return data.dual
end

function ModelAnalyzer.list_of_issues(
    data::Data,
    ::Type{ComplemetarityViolation},
)
    return data.complementarity
end

function ModelAnalyzer.list_of_issues(data::Data, ::Type{DualObjectiveMismatch})
    return data.dual_objective_mismatch
end

function ModelAnalyzer.list_of_issues(
    data::Data,
    ::Type{PrimalObjectiveMismatch},
)
    return data.primal_objective_mismatch
end

function ModelAnalyzer.list_of_issues(data::Data, ::Type{PrimalDualMismatch})
    return data.primal_dual_mismatch
end

function ModelAnalyzer.list_of_issues(
    data::Data,
    ::Type{PrimalDualSolverMismatch},
)
    return data.primal_dual_solver_mismatch
end

function _name(ref::JuMP.ConstraintRef)
    return JuMP.name(ref)
end

function _name(ref::JuMP.VariableRef)
    return JuMP.name(ref)
end

function ModelAnalyzer.list_of_issue_types(data::Data)
    ret = Type[]
    for type in (
        PrimalViolation,
        DualViolation,
        ComplemetarityViolation,
        DualObjectiveMismatch,
        PrimalObjectiveMismatch,
        PrimalDualMismatch,
        PrimalDualSolverMismatch,
    )
        if !isempty(ModelAnalyzer.list_of_issues(data, type))
            push!(ret, type)
        end
    end
    return ret
end

function summarize_configurations(io::IO, data::Data)
    print(io, "## Configuration\n\n")
    # print(io, "  - point: ", data.point, "\n")
    print(io, "  atol: ", data.atol, "\n")
    print(io, "  skip_missing: ", data.skip_missing, "\n")
    return
end

function ModelAnalyzer.summarize(
    io::IO,
    data::Data;
    verbose = true,
    max_issues = typemax(Int),
    configurations = true,
)
    print(io, "## Feasibility Analysis\n\n")
    if configurations
        summarize_configurations(io, data)
        print(io, "\n")
    end
    # add maximum primal, dual and compl
    # add sum of primal, dual and compl
    for issue_type in ModelAnalyzer.list_of_issue_types(data)
        issues = ModelAnalyzer.list_of_issues(data, issue_type)
        print(io, "\n\n")
        ModelAnalyzer.summarize(
            io,
            issues,
            verbose = verbose,
            max_issues = max_issues,
        )
    end
    return
end

function Base.show(io::IO, data::Data)
    n = sum(
        length(ModelAnalyzer.list_of_issues(data, T)) for
        T in ModelAnalyzer.list_of_issue_types(data);
        init = 0,
    )
    return print(io, "Feasibility analysis found $n issues")
end

function ModelAnalyzer.analyze(
    ::Analyzer,
    model::JuMP.GenericModel;
    primal_point = nothing,
    dual_point = nothing,
    atol::Float64 = 1e-6,
    skip_missing::Bool = false,
    dual_check = true,
)
    data = Data(
        primal_point = primal_point,
        dual_point = dual_point,
        atol = atol,
        skip_missing = skip_missing,
        dual_check = dual_check,
    )

    if data.primal_point === nothing
        if !(
            JuMP.primal_status(model) in
            (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        )
            error(
                "No primal solution is available. You must provide a point at " *
                "which to check feasibility.",
            )
        end
        data.primal_point = _last_primal_solution(model)
    end

    can_dualize = _can_dualize(model)
    if data.dual_point === nothing && can_dualize && dual_check
        if !(
            JuMP.dual_status(model) in
            (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        )
            error(
                "No dual solution is available. You must provide a point at " *
                "which to check feasibility. Or set dual_check = false.",
            )
        end
        data.dual_point = _last_dual_solution(model)
    end

    _dual_model = if can_dualize && dual_check
        _dualize2(model)
    else
        nothing
    end

    _analyze_primal!(model, data)
    if can_dualize && dual_check
        _analyze_dual!(model, _dual_model, data)
    end
    if data.dual_point !== nothing
        _analyze_complementarity!(model, data)
    end
    _analyze_objectives!(model, _dual_model, data)
    sort!(data.primal, by = x -> abs(x.violation))
    sort!(data.dual, by = x -> abs(x.violation))
    sort!(data.complementarity, by = x -> abs(x.violation))
    return data
end

function _analyze_primal!(model, data)
    dict = JuMP.primal_feasibility_report(
        model,
        data.primal_point;
        atol = data.atol,
        skip_missing = data.skip_missing,
    )
    for (ref, violation) in dict
        push!(data.primal, PrimalViolation(ref, violation))
    end
    return
end

function _analyze_dual!(model, _dual_model, data)
    dict = dual_feasibility_report(
        model,
        data.dual_point;
        atol = data.atol,
        skip_missing = data.skip_missing,
        _dual_model = _dual_model,
    )
    for (ref, violation) in dict
        push!(data.dual, DualViolation(ref, violation))
    end
    return
end

function _analyze_complementarity!(model, data)
    constraint_list =
        JuMP.all_constraints(model; include_variable_in_set_constraints = true)
    for con in constraint_list
        obj = JuMP.constraint_object(con)
        func = obj.func
        set = obj.set
        func_val =
            JuMP.value.(x -> data.primal_point[x], func) - _set_value(set)
        comp_val = MOI.Utilities.set_dot(func_val, data.dual_point[con], set)
        if abs(comp_val) > data.atol
            push!(data.complementarity, ComplemetarityViolation(con, comp_val))
        end
    end
    return
end

# not needed because it would have stoped in dualization before
# function _set_value(set::MOI.AbstractScalarSet)
#     return 0.0
# end
# function _set_value(set::MOI.Interval)
#     error("Interval sets are not supported.")
#     return (set.lower, set.upper)
# end

function _set_value(set::MOI.AbstractVectorSet)
    return zeros(MOI.dimension(set))
end

function _set_value(set::MOI.LessThan)
    return set.upper
end

function _set_value(set::MOI.GreaterThan)
    return set.lower
end

function _set_value(set::MOI.EqualTo)
    return set.value
end

function _analyze_objectives!(
    model::JuMP.GenericModel{T},
    dual_model,
    data,
) where {T}
    if JuMP.primal_status(model) in
       (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        obj_val_solver = JuMP.objective_value(model)
    else
        obj_val_solver = nothing
    end
    if JuMP.dual_status(model) in
       (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        dual_obj_val_solver = JuMP.dual_objective_value(model)
    else
        dual_obj_val_solver = nothing
    end

    obj_func = JuMP.objective_function(model)
    obj_val = JuMP.value(x -> data.primal_point[x], obj_func)

    if obj_val_solver !== nothing &&
       !isapprox(obj_val, obj_val_solver; atol = data.atol)
        push!(
            data.primal_objective_mismatch,
            PrimalObjectiveMismatch(obj_val, obj_val_solver),
        )
    end

    if dual_obj_val_solver !== nothing &&
       obj_val_solver !== nothing &&
       !isapprox(obj_val_solver, dual_obj_val_solver; atol = data.atol)
        push!(
            data.primal_dual_solver_mismatch,
            PrimalDualSolverMismatch(obj_val_solver, dual_obj_val_solver),
        )
    end

    if dual_model !== nothing && data.dual_point !== nothing
        dual_point_in_dual_model_ref =
            _dual_point_to_dual_model_ref(dual_model, data.dual_point)
        dual_obj_val = JuMP.value(
            x -> dual_point_in_dual_model_ref[x],
            JuMP.objective_function(dual_model),
        )

        if dual_obj_val_solver !== nothing &&
           !isapprox(dual_obj_val, dual_obj_val_solver; atol = data.atol)
            push!(
                data.dual_objective_mismatch,
                DualObjectiveMismatch(dual_obj_val, dual_obj_val_solver),
            )
        end

        if !isapprox(obj_val, dual_obj_val; atol = data.atol)
            push!(
                data.primal_dual_mismatch,
                PrimalDualMismatch(obj_val, dual_obj_val),
            )
        end
    end

    return
end

###

# unsafe as is its checked upstream
function _last_primal_solution(model::JuMP.GenericModel)
    return Dict(v => JuMP.value(v) for v in JuMP.all_variables(model))
end

function _last_dual_solution(model::JuMP.GenericModel{T}) where {T}
    if !JuMP.has_duals(model)
        error(
            "No dual solution is available. You must provide a point at " *
            "which to check feasibility.",
        )
    end
    constraint_list =
        JuMP.all_constraints(model; include_variable_in_set_constraints = true)
    ret = Dict{JuMP.ConstraintRef,Vector{T}}()
    for c in constraint_list
        _dual = JuMP.dual(c)
        if typeof(_dual) == Vector{T}
            ret[c] = _dual
        else
            ret[c] = T[_dual]
        end
    end
    return ret
end

"""
    dual_feasibility_report(
        model::GenericModel{T},
        point::AbstractDict{GenericVariableRef{T},T} = _last_dual_solution(model),
        atol::T = zero(T),
        skip_missing::Bool = false,
    )::Dict{Any,T}

Given a dictionary `point`, which maps variables to dual values, return a
dictionary whose keys are the constraints with an infeasibility greater than the
supplied tolerance `atol`. The value corresponding to each key is the respective
infeasibility. Infeasibility is defined as the distance between the dual
value of the constraint (see `MOI.ConstraintDual`) and the nearest point by
Euclidean distance in the corresponding set.

## Notes

 * If `skip_missing = true`, constraints containing variables that are not in
   `point` will be ignored.
 * If `skip_missing = false` and a partial dual solution is provided, an error
   will be thrown.
 * If no point is provided, the dual solution from the last time the model was
   solved is used.

## Example

```jldoctest
julia> model = Model();

julia> @variable(model, 0.5 <= x <= 1);

julia> dual_feasibility_report(model, Dict(x => 0.2))
XXXX
```
"""
function dual_feasibility_report(
    model::JuMP.GenericModel{T},
    point::AbstractDict = _last_dual_solution(model);
    atol::T = zero(T),
    skip_missing::Bool = false,
    _dual_model = nothing, # helps to avoid dualizing twice
) where {T}
    if JuMP.num_nonlinear_constraints(model) > 0
        error(
            "Nonlinear constraints are not supported. " *
            "Use `dual_feasibility_report` instead.",
        )
    end
    if !skip_missing
        constraint_list = JuMP.all_constraints(
            model;
            include_variable_in_set_constraints = true,
        )
        for c in constraint_list
            if !haskey(point, c)
                error(
                    "point does not contain a dual for constraint $c. Provide " *
                    "a dual, or pass `skip_missing = true`.",
                )
            end
        end
    end
    dual_model = if _dual_model !== nothing
        _dual_model
    else
        _dualize2(model)
    end
    dual_point = _dual_point_to_dual_model_ref(dual_model, point)

    dual_con_to_violation = JuMP.primal_feasibility_report(
        dual_model,
        dual_point;
        atol = atol,
        skip_missing = skip_missing,
    )

    # some dual model constraints are associated with primal model variables (primal_con_dual_var)
    # if variable is free (almost a primal con = ConstraintIndex{MOI.VariableIndex, MOI.Reals})
    primal_var_dual_con =
        dual_model.ext[:dualization_primal_dual_map].primal_var_dual_con
    # if variable is bounded
    primal_convar_dual_con =
        dual_model.ext[:dualization_primal_dual_map].constrained_var_dual
    # other dual model constraints (bounds) are associated with primal model constraints (non-bounds)
    primal_con_dual_convar =
        dual_model.ext[:dualization_primal_dual_map].primal_con_dual_con

    dual_con_primal_all = _build_dual_con_primal_all(
        primal_var_dual_con,
        primal_convar_dual_con,
        primal_con_dual_convar,
    )

    ret = _fix_ret(dual_con_to_violation, model, dual_con_primal_all)

    return ret
end

function _dual_point_to_dual_model_ref(
    dual_model::JuMP.GenericModel{T},
    point,
) where {T}

    # point is a:
    # dict mapping primal constraints to (dual) values
    # we need to convert it to a:
    # dict mapping the dual model variables to these (dual) values

    primal_con_dual_var =
        dual_model.ext[:dualization_primal_dual_map].primal_con_dual_var
    primal_con_dual_convar =
        dual_model.ext[:dualization_primal_dual_map].primal_con_dual_con

    dual_point = Dict{JuMP.GenericVariableRef{T},T}()
    for (jump_con, val) in point
        moi_con = JuMP.index(jump_con)
        if haskey(primal_con_dual_var, moi_con)
            vec_vars = primal_con_dual_var[moi_con]
            for (i, moi_var) in enumerate(vec_vars)
                jump_var = JuMP.VariableRef(dual_model, moi_var)
                dual_point[jump_var] = val[i]
            end
        elseif haskey(primal_con_dual_convar, moi_con)
            moi_convar = primal_con_dual_convar[moi_con]
            jump_var = JuMP.VariableRef(
                dual_model,
                MOI.VariableIndex(moi_convar.value),
            )
            dual_point[jump_var] = val
        else
            # careful with the case where bounds do not become variables
            # error("Constraint $jump_con is not associated with a variable in the dual model.")
        end
    end
    return dual_point
end

function _build_dual_con_primal_all(
    primal_var_dual_con,
    primal_convar_dual_con,
    primal_con_dual_con,
)
    # MOI.VariableIndex here represents MOI.ConstraintIndex{MOI.VariableIndex, MOI.Reals}
    dual_con_primal_all =
        Dict{MOI.ConstraintIndex,Union{MOI.ConstraintIndex,MOI.VariableIndex}}()
    for (primal_var, dual_con) in primal_var_dual_con
        dual_con_primal_all[dual_con] = primal_var
    end
    for (primal_con, dual_con) in primal_convar_dual_con
        dual_con_primal_all[dual_con] = primal_con
    end
    for (primal_con, dual_con) in primal_con_dual_con
        dual_con_primal_all[dual_con] = primal_con
    end
    return dual_con_primal_all
end

function _fix_ret(
    pre_ret,
    primal_model::JuMP.GenericModel{T},
    dual_con_primal_all,
) where {T}
    ret = Dict{Union{JuMP.ConstraintRef,JuMP.VariableRef},Union{T,Vector{T}}}()
    for (jump_dual_con, val) in pre_ret
        # v is a variable in the dual jump model
        # we need the associated cosntraint in the primal jump model
        moi_dual_con = JuMP.index(jump_dual_con)
        moi_primal_something = dual_con_primal_all[moi_dual_con]
        if moi_primal_something isa MOI.VariableIndex
            # variable in the dual model
            # constraint in the primal model
            jump_primal_var =
                JuMP.VariableRef(primal_model, moi_primal_something)
            # ret[jump_primal_var] = T[val]
            ret[jump_primal_var] = val
        else
            # constraint in the primal model
            jump_primal_con = JuMP.constraint_ref_with_index(
                primal_model,
                moi_primal_something,
            )
            # if val isa Vector
            #     ret[jump_primal_con] = val
            # else
            #     ret[jump_primal_con] = T[val]
            # end
            ret[jump_primal_con] = val
        end
    end
    return ret
end

function _dualize2(
    model::JuMP.GenericModel,
    optimizer_constructor = nothing;
    kwargs...,
)
    mode = JuMP.mode(model)
    if mode == JuMP.MANUAL
        error("Dualization does not support solvers in $(mode) mode")
    end
    dual_model = JuMP.Model()
    dual_problem = Dualization.DualProblem(JuMP.backend(dual_model))
    Dualization.dualize(JuMP.backend(model), dual_problem; kwargs...)
    Dualization._fill_obj_dict_with_variables!(dual_model)
    Dualization._fill_obj_dict_with_constraints!(dual_model)
    if optimizer_constructor !== nothing
        JuMP.set_optimizer(dual_model, optimizer_constructor)
    end
    dual_model.ext[:dualization_primal_dual_map] = dual_problem.primal_dual_map
    return dual_model
end

function _can_dualize(model::JuMP.GenericModel)
    types = JuMP.list_of_constraint_types(model)

    for (_F, S) in types
        F = JuMP.moi_function_type(_F)
        if !Dualization.supported_constraint(F, S)
            return false
        end
    end

    _F = JuMP.objective_function_type(model)
    F = JuMP.moi_function_type(_F)

    if !Dualization.supported_obj(F)
        return false
    end

    if JuMP.num_nonlinear_constraints(model) > 0
        return false
    end

    if JuMP.objective_sense(model) == MOI.FEASIBILITY_SENSE
        return false
    end

    return true
end

end # module
