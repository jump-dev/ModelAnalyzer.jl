# Copyright (c) 2025: Joaquim Garcia, Oscar Dowson and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

Base.@kwdef mutable struct CoefficientsData
    threshold_dense_fill_in::Float64 = 0.10
    threshold_dense_entries::Int = 1000
    threshold_small::Float64 = 1e-5
    threshold_large::Float64 = 1e+5

    number_of_variables::Int = 0
    number_of_constraints::Int = 0

    constraint_info::Vector{Tuple{DataType,DataType,Int}} =
        Tuple{DataType,DataType,Int}[]

    matrix_nnz::Int = 0

    matrix_range::Vector{Float64} = sizehint!(Float64[1.0, 1.0], 2)
    bounds_range::Vector{Float64} = sizehint!(Float64[1.0, 1.0], 2)
    rhs_range::Vector{Float64} = sizehint!(Float64[1.0, 1.0], 2)
    objective_range::Vector{Float64} = sizehint!(Float64[1.0, 1.0], 2)

    variables_in_constraints::Set{VariableRef} = Set{VariableRef}()
    variables_not_in_constraints::Vector{VariableRef} = VariableRef[]

    empty_rows::Vector{ConstraintRef} = ConstraintRef[]
    bound_rows::Vector{ConstraintRef} = ConstraintRef[]
    dense_rows::Vector{Tuple{ConstraintRef,Int}} = Tuple{ConstraintRef,Int}[]

    nonconvex_rows::Vector{ConstraintRef} = ConstraintRef[]

    matrix_small::Vector{Tuple{ConstraintRef,VariableRef,Float64}} =
        Tuple{ConstraintRef,VariableRef,Float64}[]
    matrix_large::Vector{Tuple{ConstraintRef,VariableRef,Float64}} =
        Tuple{ConstraintRef,VariableRef,Float64}[]

    bounds_small::Vector{Tuple{VariableRef,Float64}} =
        Tuple{VariableRef,Float64}[]
    bounds_large::Vector{Tuple{VariableRef,Float64}} =
        Tuple{VariableRef,Float64}[]

    rhs_small::Vector{Tuple{ConstraintRef,Float64}} =
        Tuple{ConstraintRef,Float64}[]
    rhs_large::Vector{Tuple{ConstraintRef,Float64}} =
        Tuple{ConstraintRef,Float64}[]

    objective_small::Vector{Tuple{VariableRef,Float64}} =
        Tuple{VariableRef,Float64}[]
    objective_large::Vector{Tuple{VariableRef,Float64}} =
        Tuple{VariableRef,Float64}[]

    has_quadratic_objective::Bool = false
    has_quadratic_constraints::Bool = false

    objective_quadratic_range = sizehint!(Float64[1.0, 1.0], 2)
    matrix_quadratic_range = sizehint!(Float64[1.0, 1.0], 2)

    matrix_quadratic_small::Vector{
        Tuple{ConstraintRef,VariableRef,VariableRef,Float64},
    } = Tuple{ConstraintRef,VariableRef,VariableRef,Float64}[]
    matrix_quadratic_large::Vector{
        Tuple{ConstraintRef,VariableRef,VariableRef,Float64},
    } = Tuple{ConstraintRef,VariableRef,VariableRef,Float64}[]
    objective_quadratic_small::Vector{Tuple{VariableRef,VariableRef,Float64}} =
        Tuple{VariableRef,VariableRef,Float64}[]
    objective_quadratic_large::Vector{Tuple{VariableRef,VariableRef,Float64}} =
        Tuple{VariableRef,VariableRef,Float64}[]
end

function _update_range(range::Vector{Float64}, value::Number)
    range[1] = min(range[1], abs(value))
    range[2] = max(range[2], abs(value))
    return 1
end

function _get_constraint_data(
    data,
    ref::ConstraintRef,
    func::JuMP.GenericAffExpr,
)
    if length(func.terms) == 1
        if first(values(func.terms)) ≈ 1.0
            push!(data.bound_rows, ref)
            data.matrix_nnz += 1
            return
        end
    end
    nnz = 0
    for (variable, coefficient) in func.terms
        if coefficient ≈ 0.0
            continue
        end
        nnz += _update_range(data.matrix_range, coefficient)
        if abs(coefficient) < data.threshold_small
            push!(data.matrix_small, (ref, variable, coefficient))
        elseif abs(coefficient) > data.threshold_large
            push!(data.matrix_large, (ref, variable, coefficient))
        end
        push!(data.variables_in_constraints, variable)
    end
    if nnz == 0
        push!(data.empty_rows, ref)
        return
    end
    if nnz / data.number_of_variables > data.threshold_dense_fill_in &&
       nnz > data.threshold_dense_entries
        push!(data.dense_rows, (ref, nnz))
    end
    data.matrix_nnz += nnz
    return
end

# function _update_range(range::Vector, func::JuMP.GenericAffExpr)
#     _update_range(range, func.constant)
#     return true
# end

function _get_variable_data(data, variable, coefficient::Number)
    if !(coefficient ≈ 0.0)
        _update_range(data.bounds_range, coefficient)
        if abs(coefficient) < data.threshold_small
            push!(data.bounds_small, (variable, coefficient))
        elseif abs(coefficient) > data.threshold_large
            push!(data.bounds_large, (variable, coefficient))
        end
    end
    return
end

function _get_objective_data(data, func::JuMP.GenericAffExpr)
    nnz = 0
    for (variable, coefficient) in func.terms
        if coefficient ≈ 0.0
            continue
        end
        nnz += _update_range(data.objective_range, coefficient)
        if abs(coefficient) < data.threshold_small
            push!(data.objective_small, (variable, coefficient))
        elseif abs(coefficient) > data.threshold_large
            push!(data.objective_large, (variable, coefficient))
        end
    end
    return
end

function _get_constraint_data(data, func::Vector{JuMP.GenericAffExpr}, set)
    for f in func
        _get_constraint_data(data, ref, f, set)
    end
    return true
end

function _get_constraint_data(data, ref, func::JuMP.GenericAffExpr, set)
    coefficient = func.constant
    if coefficient ≈ 0.0
        return
    end
    _update_range(data.rhs_range, coefficient)
    if abs(coefficient) < data.threshold_small
        push!(data.rhs_small, (ref, coefficient))
    elseif abs(coefficient) > data.threshold_large
        push!(data.rhs_large, (ref, coefficient))
    end
    return
end

function _get_constraint_data(
    data,
    ref,
    func::JuMP.GenericAffExpr,
    set::MOI.LessThan,
)
    coefficient = set.upper - func.constant
    if coefficient ≈ 0.0
        return
    end
    _update_range(data.rhs_range, coefficient)
    if abs(coefficient) < data.threshold_small
        push!(data.rhs_small, (ref, coefficient))
    elseif abs(coefficient) > data.threshold_large
        push!(data.rhs_large, (ref, coefficient))
    end
    return
end

function _get_constraint_data(
    data,
    ref,
    func::JuMP.GenericAffExpr,
    set::MOI.GreaterThan,
)
    coefficient = set.lower - func.constant
    if coefficient ≈ 0.0
        return
    end
    _update_range(data.rhs_range, coefficient)
    if abs(coefficient) < data.threshold_small
        push!(data.rhs_small, (ref, coefficient))
    elseif abs(coefficient) > data.threshold_large
        push!(data.rhs_large, (ref, coefficient))
    end
    return
end

function _get_constraint_data(
    data,
    ref,
    func::JuMP.GenericAffExpr,
    set::MOI.EqualTo,
)
    coefficient = set.value - func.constant
    if coefficient ≈ 0.0
        return
    end
    _update_range(data.rhs_range, coefficient)
    if abs(coefficient) < data.threshold_small
        push!(data.rhs_small, (ref, coefficient))
    elseif abs(coefficient) > data.threshold_large
        push!(data.rhs_large, (ref, coefficient))
    end
    return
end

function _get_constraint_data(
    data,
    ref,
    func::JuMP.GenericAffExpr,
    set::MOI.Interval,
)
    coefficient = set.upper - func.constant
    if !(coefficient ≈ 0.0)
        _update_range(data.rhs_range, coefficient)
        if abs(coefficient) < data.threshold_small
            push!(data.rhs_small, (ref, coefficient))
        elseif abs(coefficient) > data.threshold_large
            push!(data.rhs_large, (ref, coefficient))
        end
    end
    coefficient = set.lower - func.constant
    if coefficient ≈ 0.0
        return
    end
    _update_range(data.rhs_range, coefficient)
    if abs(coefficient) < data.threshold_small
        push!(data.rhs_small, (ref, coefficient))
    elseif abs(coefficient) > data.threshold_large
        push!(data.rhs_large, (ref, coefficient))
    end
    return
end

function _get_constraint_data(data, func::Vector{VariableRef})
    for var in func
        push!(data.variables_in_constraints, var)
    end
    return
end

# Default fallback for unsupported constraints.
_update_range(data, func, set) = false

function coefficient_analysis(model::JuMP.Model)
    data = CoefficientsData()
    data.number_of_variables = JuMP.num_variables(model)
    sizehint!(data.variables_in_constraints, data.number_of_variables)
    data.number_of_constraints =
        JuMP.num_constraints(model, count_variable_in_set_constraints = false)
    _get_objective_data(data, JuMP.objective_function(model))
    for var in JuMP.all_variables(model)
        if JuMP.has_lower_bound(var)
            _get_variable_data(data, var, JuMP.lower_bound(var))
        end
        if JuMP.has_upper_bound(var)
            _get_variable_data(data, var, JuMP.upper_bound(var))
        end
    end
    for (F, S) in JuMP.list_of_constraint_types(model)
        n = JuMP.num_constraints(model, F, S)
        if n > 0
            push!(data.constraint_info, (F, S, n))
        end
        F == JuMP.VariableRef && continue
        if F == Vector{JuMP.VariableRef}
            for con in JuMP.all_constraints(model, F, S)
                con_obj = JuMP.constraint_object(con)
                _get_constraint_data(data, con_obj.func)
            end
            continue
        end
        for con in JuMP.all_constraints(model, F, S)
            con_obj = JuMP.constraint_object(con)
            _get_constraint_data(data, con, con_obj.func)
            _get_constraint_data(data, con, con_obj.func, con_obj.set)
        end
    end
    for var in JuMP.all_variables(model)
        if !(var in data.variables_in_constraints)
            push!(data.variables_not_in_constraints, var)
        end
    end
    sort!(data.dense_rows, by = x -> x[2], rev = true)
    sort!(data.matrix_small, by = x -> abs(x[3]))
    sort!(data.matrix_large, by = x -> abs(x[3]), rev = true)
    sort!(data.bounds_small, by = x -> abs(x[2]))
    sort!(data.bounds_large, by = x -> abs(x[2]), rev = true)
    sort!(data.rhs_small, by = x -> abs(x[2]))
    sort!(data.rhs_large, by = x -> abs(x[2]), rev = true)
    sort!(data.objective_small, by = x -> abs(x[2]))
    sort!(data.objective_large, by = x -> abs(x[2]), rev = true)
    return data
end

# printing

_print_value(x::Real) = Printf.@sprintf("%1.0e", x)

function _stringify_bounds(bounds::Vector{Float64})
    lower = bounds[1] < Inf ? _print_value(bounds[1]) : "0e+00"
    upper = bounds[2] > -Inf ? _print_value(bounds[2]) : "0e+00"
    return string("[", lower, ", ", upper, "]")
end

function _print_coefficients(
    io::IO,
    name::String,
    data,
    range,
    warnings::Vector{Tuple{String,String}},
)
    println(
        io,
        "    ",
        rpad(string(name, " range"), 17),
        _stringify_bounds(range),
    )
    if range[1] < data.threshold_small
        push!(warnings, (name, "small"))
    end
    if range[2] > data.threshold_large
        push!(warnings, (name, "large"))
    end
    return
end

function _print_numerical_stability_report(
    io::IO,
    data::CoefficientsData;
    warn::Bool = true,
    verbose::Bool = true,
    max_list::Int = 10,
    names = true,
)
    println(io, "Numerical stability report:")
    println(io, "  Number of variables: ", data.number_of_variables)
    println(io, "  Number of constraints: ", data.number_of_constraints)
    println(io, "  Number of nonzeros in matrix: ", data.matrix_nnz)

    # types
    println(io, "  Constraint types:")
    for (F, S, n) in data.constraint_info
        println(io, "    * ", F, "-", S, ": ", n)
    end

    println(io, "  Thresholds:")
    println(io, "    Dense rows (fill-in): ", data.threshold_dense_fill_in)
    println(io, "    Dense rows (entries): ", data.threshold_dense_entries)
    println(io, "    Small coefficients: ", data.threshold_small)
    println(io, "    Large coefficients: ", data.threshold_large)

    println(io, "  Coefficient ranges:")
    warnings = Tuple{String,String}[]
    _print_coefficients(io, "matrix", data, data.matrix_range, warnings)
    _print_coefficients(io, "objective", data, data.objective_range, warnings)
    _print_coefficients(io, "bounds", data, data.bounds_range, warnings)
    _print_coefficients(io, "rhs", data, data.rhs_range, warnings)

    # rows that should be bounds
    println(
        io,
        "  Variables not in constraints: ",
        length(data.variables_not_in_constraints),
    )
    println(io, "  Bound rows: ", length(data.bound_rows))
    println(io, "  Dense constraints: ", length(data.dense_rows))
    println(io, "  Empty constraints: ", length(data.empty_rows))
    println(io, "  Coefficients:")
    println(io, "    matrix small: ", length(data.matrix_small))
    println(io, "    matrix large: ", length(data.matrix_large))
    println(io, "    bounds small: ", length(data.bounds_small))
    println(io, "    bounds large: ", length(data.bounds_large))
    println(io, "    rhs small: ", length(data.rhs_small))
    println(io, "    rhs large: ", length(data.rhs_large))
    println(io, "    objective small: ", length(data.objective_small))
    println(io, "    objective large: ", length(data.objective_large))

    if verbose
        println(io, "\n  Variables not in constraints:")
        for var in first(data.variables_not_in_constraints, max_list)
            println(io, "    * ", var, _name_string(var, names))
        end
        println(io, "\n  Bound rows:")
        for ref in first(data.bound_rows, max_list)
            println(io, "    * ", _name_string(ref, names), name_str)
        end
        println(io, "\n  Dense constraints:")
        for (ref, nnz) in first(data.dense_rows, max_list)
            println(io, "    * ", ref, _name_string(ref, names), ": ", nnz)
        end
        println(io, "\n  Empty constraints:")
        for ref in first(data.empty_rows, max_list)
            println(io, "    * ", _name_string(ref, names), name_str)
        end
        println(io, "\n  Small matrix coefficients:")
        for (ref, var, coeff) in first(data.matrix_small, max_list)
            con_str = _name_string(ref, names)
            var_str = _name_string(var, names)
            println(io, "    * ", ref, con_str, "-", var, var_str, ": ", coeff)
        end
        println(io, "\n  Large matrix coefficients:")
        for (ref, var, coeff) in first(data.matrix_large, max_list)
            con_str = _name_string(ref, names)
            var_str = _name_string(var, names)
            println(io, "    * ", ref, con_str, "-", var, var_str, ": ", coeff)
        end
        println(io, "\n  Small bounds coefficients:")
        for (var, coeff) in first(data.bounds_small, max_list)
            println(io, "    * ", var, _name_string(var, names), ": ", coeff)
        end
        println(io, "\n  Large bounds coefficients:")
        for (var, coeff) in first(data.bounds_large, max_list)
            println(io, "    * ", var, _name_string(var, names), ": ", coeff)
        end
        println(io, "\n  Small rhs coefficients:")
        for (ref, coeff) in first(data.rhs_small, max_list)
            println(io, "    * ", ref, _name_string(ref, names), ": ", coeff)
        end
        println(io, "\n  Large rhs coefficients:")
        for (ref, coeff) in first(data.rhs_large, max_list)
            println(io, "    * ", ref, _name_string(ref, names), ": ", coeff)
        end
        println(io, "\n  Small objective coefficients:")
        for (var, coeff) in first(data.objective_small, max_list)
            println(io, "    * ", var, _name_string(var, names), ": ", coeff)
        end
        println(io, "\n  Large objective coefficients:")
        for (var, coeff) in first(data.objective_large, max_list)
            println(io, "    * ", var, _name_string(var, names), ": ", coeff)
        end
    end

    if warn && !isempty(warnings)
        println(io, "\nWARNING: numerical stability issues detected")
        for (name, sense) in warnings
            println(io, "  - $(name) range contains $(sense) coefficients")
        end
        println(
            io,
            "Very large or small absolute values of coefficients\n",
            "can cause numerical stability issues. Consider\n",
            "reformulating the model.",
        )
    end
    return
end

function _name_string(ref, names)
    if names
        return string(" (", JuMP.name(ref), ')')
    end
    return ""
end

function Base.show(io::IO, data::CoefficientsData; verbose::Bool = false)
    _print_numerical_stability_report(io, data, warn = true, verbose = verbose)
    return
end
