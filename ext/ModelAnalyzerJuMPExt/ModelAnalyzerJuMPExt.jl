# Copyright (c) 2025: Joaquim Garcia, Oscar Dowson and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module ModelAnalyzerJuMPExt

import JuMP
import MathOptInterface as MOI
import ModelAnalyzer

function ModelAnalyzer.analyze(
    analyzer::ModelAnalyzer.AbstractAnalyzer,
    model::JuMP.GenericModel;
    kwargs...,
)
    moi_model = JuMP.backend(model)
    result = ModelAnalyzer.analyze(analyzer, moi_model; kwargs...)
    return result
end

function ModelAnalyzer._name(
    ref::MOI.VariableIndex,
    model::JuMP.GenericModel{T},
) where {T}
    jump_ref = JuMP.GenericVariableRef{T}(model, ref)
    name = JuMP.name(jump_ref)
    if !isempty(name)
        return name
    end
    return "$jump_ref"
end

function ModelAnalyzer._name(ref::MOI.ConstraintIndex, model::JuMP.GenericModel)
    jump_ref = JuMP.constraint_ref_with_index(model, ref)
    name = JuMP.name(jump_ref)
    if !isempty(name)
        return name
    end
    return "$jump_ref"
end

"""
    variable(issue::ModelAnalyzer.AbstractIssue, model::JuMP.GenericModel)

Return the **JuMP** variable reference associated to a particular issue.
"""
function ModelAnalyzer.variable(
    issue::ModelAnalyzer.AbstractIssue,
    model::JuMP.GenericModel{T},
) where {T}
    ref = ModelAnalyzer.variable(issue)
    return JuMP.GenericVariableRef{T}(model, ref)
end

"""
    variables(issue::ModelAnalyzer.AbstractIssue, model::JuMP.GenericModel)

Return the **JuMP** variable references associated to a particular issue.
"""
function ModelAnalyzer.variables(
    issue::ModelAnalyzer.AbstractIssue,
    model::JuMP.GenericModel{T},
) where {T}
    refs = ModelAnalyzer.variables(issue)
    return JuMP.GenericVariableRef{T}.(model, refs)
end

"""
    constraint(issue::ModelAnalyzer.AbstractIssue, model::JuMP.GenericModel)

Return the **JuMP** constraint reference associated to a particular issue.
"""
function ModelAnalyzer.constraint(
    issue::ModelAnalyzer.AbstractIssue,
    model::JuMP.GenericModel,
)
    ref = ModelAnalyzer.constraint(issue)
    return JuMP.constraint_ref_with_index(model, ref)
end

"""
    constraintss(issue::ModelAnalyzer.AbstractIssue, model::JuMP.GenericModel)

Return the **JuMP** constraints reference associated to a particular issue.
"""
function ModelAnalyzer.constraints(
    issue::ModelAnalyzer.AbstractIssue,
    model::JuMP.GenericModel,
)
    ref = ModelAnalyzer.constraints(issue)
    return JuMP.constraint_ref_with_index.(model, ref)
end

end # module ModelAnalyzerJuMPExt
