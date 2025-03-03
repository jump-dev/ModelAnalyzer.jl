# Copyright (c) 2025: Joaquim Garcia, Oscar Dowson and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import ModelAnalyzer
import MathOptInterface as MOI
using Test
using JuMP
import HiGHS

model = Model()
@variable(model, x <= 1e9)
@variable(model, y >= 1e-9)
@constraint(model, x + y <= 1e8)
@constraint(model, x + y + 1e7 <= 2)
@constraint(model, 1e6 * x + 1e-5 * y >= 2)
@constraint(model, x <= 100)
@objective(model, Max, x + y)

data = ModelAnalyzer.coefficient_analysis(model)

show(data)
