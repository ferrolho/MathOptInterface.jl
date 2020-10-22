# Used for dispatching
abstract type PrintMode end
abstract type REPLMode <: PrintMode end
abstract type IJuliaMode <: PrintMode end

# REPL-specific symbols
# Anything here: https://en.wikipedia.org/wiki/Windows-1252
# should probably work fine on Windows
function _math_symbol(::Type{REPLMode}, name::Symbol)
    if name == :leq
        return Sys.iswindows() ? "<=" : "≤"
    elseif name == :geq
        return Sys.iswindows() ? ">=" : "≥"
    elseif name == :eq
        return Sys.iswindows() ? "==" : "="
    elseif name == :times
        return "*"
    elseif name == :sq
        return "²"
    elseif name == :ind_open
        return "["
    elseif name == :ind_close
        return "]"
    elseif name == :for_all
        return Sys.iswindows() ? "for all" : "∀"
    elseif name == :in
        return Sys.iswindows() ? "in" : "∈"
    elseif name == :open_set
        return "{"
    elseif name == :dots
        return Sys.iswindows() ? ".." : "…"
    elseif name == :close_set
        return "}"
    elseif name == :union
        return Sys.iswindows() ? "or" : "∪"
    elseif name == :infty
        return Sys.iswindows() ? "Inf" : "∞"
    elseif name == :open_rng
        return "["
    elseif name == :close_rng
        return "]"
    elseif name == :integer
        return "integer"
    elseif name == :succeq0
        return " is semidefinite"
    elseif name == :Vert
        return Sys.iswindows() ? "||" : "‖"
    elseif name == :sub2
        return Sys.iswindows() ? "_2" : "₂"
    else
        error("Internal error: Unrecognized symbol $name.")
    end
end

# IJulia-specific symbols.
function _math_symbol(::Type{IJuliaMode}, name::Symbol)
    if name == :leq
        return "\\leq"
    elseif name == :geq
        return "\\geq"
    elseif name == :eq
        return "="
    elseif name == :times
        return "\\times "
    elseif name == :sq
        return "^2"
    elseif name == :ind_open
        return "_{"
    elseif name == :ind_close
        return "}"
    elseif name == :for_all
        return "\\quad\\forall"
    elseif name == :in
        return "\\in"
    elseif name == :open_set
        return "\\{"
    elseif name == :dots
        return "\\dots"
    elseif name == :close_set
        return "\\}"
    elseif name == :union
        return "\\cup"
    elseif name == :infty
        return "\\infty"
    elseif name == :open_rng
        return "\\["
    elseif name == :close_rng
        return "\\]"
    elseif name == :integer
        return "\\in \\mathbb{Z}"
    elseif name == :succeq0
        return "\\succeq 0"
    elseif name == :Vert
        return "\\Vert"
    elseif name == :sub2
        return "_2"
    else
        error("Internal error: Unrecognized symbol $name.")
    end
end

Base.show(io::IO, model::ModelLike) = Utilities.print_with_acronym(io, summary(model))

# Helper function that rounds carefully for the purposes of printing
# e.g.   5.3  =>  5.3
#        1.0  =>  1
function _string_round(print_mode, f::AbstractFloat)
    iszero(f) && return "0" # strip sign off zero
    str = string(f)
    if print_mode === IJuliaMode
        exp_idx = findfirst(isequal('e'), str)
        if exp_idx !== nothing
            str = string(str[1:(exp_idx - 1)], " \\times 10^{", str[(exp_idx + 1):end], "}")
        end
    end
    return length(str) >= 2 && str[end-1:end] == ".0" ? str[1:end-2] : str
end
_string_round(print_mode, f) = string(f)

_wrap_in_math_mode(str) = "\$\$ $str \$\$"
_wrap_in_inline_math_mode(str) = "\$ $str \$"

function Base.print(io::IO, model::ModelLike; variable_name = Base.get(io, :variable_name, name_or_noname))
    print(io, model_string(REPLMode, model, variable_name))
end
function Base.show(io::IO, ::MIME"text/latex", model::ModelLike; variable_name = Base.get(io, :variable_name, name_or_noname))
    print(io, _wrap_in_math_mode(model_string(IJuliaMode, model, variable_name)))
end

function model_string(print_mode, model::ModelLike, variable_name = name_or_noname)
    ijl = print_mode == IJuliaMode
    sep = ijl ? " & " : " "
    eol = ijl ? "\\\\\n" : "\n"
    sense = get(model, ObjectiveSense())
    str = ""
    if sense == MAX_SENSE
        str *= ijl ? "\\max" : "Max"
    elseif sense == MIN_SENSE
        str *= ijl ? "\\min" : "Min"
    else
        str *= ijl ? "\\text{feasibility}" : "Feasibility"
    end
    if sense != FEASIBILITY_SENSE
        if ijl
            str *= "\\quad"
        end
        str *= sep
        str *= objective_function_string(print_mode, model, variable_name)
    end
    str *= eol
    str *= ijl ? "\\text{Subject to} \\quad" : "Subject to" * eol
    constraints = constraints_string(print_mode, model, variable_name)
    if print_mode == REPLMode
        constraints = map(str -> replace(str, '\n' => eol * sep), constraints)
    end
    if !isempty(constraints)
        str *= sep
    end
    str *= join(constraints, eol * sep)
    if !isempty(constraints)
        str *= eol
    end
    if ijl
        str = "\\begin{alignat*}{1}" * str * "\\end{alignat*}\n"
    end
    return str
end

"""
    constraints_string(print_mode, model::MOI.ModelLike)::Vector{String}

Return a list of `String`s describing each constraint of the model.
"""
function constraints_string(print_mode, model::ModelLike, variable_name = name_or_noname)
    strings = String[]
    for (F, S) in get(model, ListOfConstraints())
        for ci in get(model, ListOfConstraintIndices{F, S}())
            push!(strings, constraint_string(print_mode, model, ci, variable_name, in_math_mode = true))
        end
    end
    return strings
end

function constraint_string(print_mode, model::ModelLike, func::AbstractFunction, set::AbstractSet, variable_name = name_or_noname)
    func_str = function_string(print_mode, model, func, variable_name)
    in_set_str = in_set_string(print_mode, set)
    if print_mode == REPLMode
        lines = split(func_str, '\n')
        lines[1 + div(length(lines), 2)] *= " " * in_set_str
        return join(lines, '\n')
    else
        return func_str * " " * in_set_str
    end
end
function constraint_string(print_mode, model::ModelLike, constraint_name,
                           func::AbstractFunction,
                           set::AbstractSet,
                           variable_name = name_or_noname;
                           in_math_mode = false)
    constraint_without_name = constraint_string(print_mode, model, func, set, variable_name)
    if print_mode == IJuliaMode && !in_math_mode
        constraint_without_name = _wrap_in_inline_math_mode(constraint_without_name)
    end
    # Names don't print well in LaTeX math mode
    if isempty(constraint_name) || (print_mode == IJuliaMode && in_math_mode)
        return constraint_without_name
    else
        return constraint_name * " : " * constraint_without_name
    end
end
function constraint_string(print_mode, model::ModelLike, ci::ConstraintIndex, variable_name = name_or_noname; in_math_mode = false)
    func = get(model, ConstraintFunction(), ci)
    set = get(model, ConstraintSet(), ci)
    if supports(model, ConstraintName(), typeof(ci))
        name = get(model, ConstraintName(), ci)
        return constraint_string(print_mode, model, name, func, set, variable_name, in_math_mode = in_math_mode)
    else
        return constraint_string(print_mode, model, func, set, variable_name, in_math_mode = in_math_mode)
    end
end

"""
    objective_function_string(print_mode, model::AbstractModel)::String

Return a `String` describing the objective function of the model.
"""
function objective_function_string(print_mode, model::ModelLike, variable_name = name_or_noname)
    objective_function_type = get(model, ObjectiveFunctionType())
    attr = ObjectiveFunction{objective_function_type}()
    objective_function = get(model, attr)
    return function_string(print_mode, model, objective_function, variable_name)
end

function name_or_noname(model, vi)
    name = get(model, VariableName(), vi)
    if isempty(name)
        return "noname"
    else
        return name
    end
end
function name_or_default_name(model, vi)
    name = get(model, VariableName(), vi)
    if isempty(name)
        return default_name(vi)
    else
        return name
    end
end

function function_string(print_mode, model::ModelLike, func::AbstractFunction, variable_name = name_or_noname)
    if supports(model, VariableName(), VariableIndex)
        return function_string(print_mode, func, vi -> variable_name(model, vi))
    else
        return function_string(print_mode, func)
    end
end

default_name(vi) = string("x[", vi.value, "]")
function_string(::Type{REPLMode}, v::VariableIndex, variable_name = default_name) = variable_name(v)
function function_string(::Type{IJuliaMode}, v::VariableIndex, variable_name = default_name)
    # TODO: This is wrong if variable name constains extra "]"
    return replace(replace(variable_name(v), "[" => "_{", count = 1), "]" => "}")
end
function_string(mode, func::SingleVariable, variable_name = default_name) = function_string(mode, func.variable, variable_name)
# Whether something is zero or not for the purposes of printing it
# oneunit is useful e.g. if coef is a Unitful quantity. The second `abs` is import if it is complex.
_is_zero_for_printing(coef) = abs(coef) < 1e-10 * abs(oneunit(coef))
# Whether something is one or not for the purposes of printing it.
_is_one_for_printing(coef) = _is_zero_for_printing(abs(coef) - oneunit(coef))
_is_one_for_printing(coef::Complex) = _is_one_for_printing(real(coef)) && _is_zero_for_printing(imag(coef))
_unary_sign_string(coef) = coef < zero(coef) ? "-" : ""
_binary_sign_string(coef) = coef < zero(coef) ? " - " : " + "
_complex_number(::Type{IJuliaMode}) = "i"
_complex_number(::Type{REPLMode}) = "im"

function _coef_string(print_mode, coef, coefficient)
    if coefficient && _is_one_for_printing(coef)
        return ""
    else
        return _string_round(print_mode, coef)
    end
end
_is_negative(coef) = false
_is_negative(coef::Real) = coef < zero(coef)
function _sign_and_string(print_mode, coef, coefficient)
    if _is_negative(coef)
        return -1, _coef_string(print_mode, -coef, coefficient)
    else
        return 1, _coef_string(print_mode, coef, coefficient)
    end
end
function _sign_and_string(print_mode, coef::Complex, coefficient::Bool)
    if iszero(real(coef))
        if iszero(imag(coef))
            return _sign_and_string(print_mode, 0, coefficient)
        else
            sign, str = _sign_and_string(print_mode, imag(coef), coefficient)
            return sign, string(str, _complex_number(print_mode), coefficient ? " " : "")
        end
    elseif iszero(imag(coef))
        return _sign_and_string(print_mode, real(coef), coefficient)
    else
        real_sign, real_string = _sign_and_string(print_mode, real(coef), coefficient)
        imag_sign, imag_string = _sign_and_string(print_mode, imag(coef), coefficient)
        return 1, string("(", _unary_sign_string(real_sign), real_string,
                         _binary_sign_string(imag_sign), imag_string,
                         _complex_number(print_mode), ")")
    end
end

function function_string(print_mode, func::ScalarAffineFunction, variable_name = default_name; show_constant=true)
    # If the expression is empty, return the constant (or 0)
    if isempty(func.terms)
        return show_constant ? _string_round(print_mode, constant(func)) : "0"
    end

    term_str = Vector{String}(undef, 2length(func.terms))
    elm = 1

    for term in func.terms
        sign, coef_str = _sign_and_string(print_mode, term.coefficient, true)
        term_str[2 * elm - 1] = elm == 1 ? _unary_sign_string(sign) : _binary_sign_string(sign)
        term_str[2 * elm] = string(coef_str, function_string(print_mode, term.variable_index, variable_name))
        elm += 1
    end

    if elm == 1
        # Will happen with cancellation of all terms
        # We should just return the constant, if its desired
        return show_constant ? _string_round(print_mode, a.constant) : "0"
    else
        ret = join(term_str[1 : 2 * (elm - 1)])
        if !_is_zero_for_printing(constant(func)) && show_constant
            sign, coef_str = _sign_and_string(print_mode, constant(func), false)
            if coef_str[end] == ' '
                coef_str = coef_str[1:end-1]
            end
            ret = string(ret, _binary_sign_string(sign), coef_str)
        end
        return ret
    end
end

function function_string(print_mode, func::AbstractVectorFunction, variable_name = default_name; kws...)
    return "[" * join(function_string.(print_mode, Utilities.scalarize(func), variable_name; kws...), ", ") * "]"
end

function Base.show(io::IO, f::AbstractFunction; variable_name = Base.get(io, :variable_name, default_name))
    print(io, function_string(REPLMode, f, variable_name))
end
function Base.show(io::IO, ::MIME"text/latex", f::AbstractFunction; variable_name = Base.get(io, :variable_name, default_name))
    print(io, _wrap_in_math_mode(function_string(IJuliaMode, f, variable_name)))
end

function in_set_string(print_mode, set::LessThan)
    return string(_math_symbol(print_mode, :leq), " ", set.upper)
end

function in_set_string(print_mode, set::GreaterThan)
    return string(_math_symbol(print_mode, :geq), " ", set.lower)
end

function in_set_string(print_mode, set::EqualTo)
    return string(_math_symbol(print_mode, :eq), " ", set.value)
end

function in_set_string(print_mode, set::Interval)
    return string(_math_symbol(print_mode, :in), " ",
                  _math_symbol(print_mode, :open_rng), set.lower, ", ",
                  set.upper, _math_symbol(print_mode, :close_rng))
end

in_set_string(print_mode, ::ZeroOne) = "binary"
in_set_string(print_mode, ::Integer) = "integer"

# TODO: Consider fancy latex names for some sets. They're currently printed as
# regular text in math mode which looks a bit awkward.
"""
    in_set_string(print_mode::Type{<:MOI.PrintMode},
                  set::MOI.AbstractSet)

Return a `String` representing the membership to the set `set` using print mode
`print_mode`.
"""
function in_set_string(print_mode, set::AbstractSet)
    return string(_math_symbol(print_mode, :in), " ", set)
end
