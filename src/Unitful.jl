"Copyright Andrew J. Keller, 2016"

module Unitful

import Base: ==, <, <=, +, -, *, /, .+, .-, .*, ./, .\, //, ^, .^
import Base: show, convert
import Base: abs, float, inv, sqrt
import Base: sin, cos, tan, cot, sec, csc
import Base: min, max, floor, ceil

import Base: mod, rem, div, fld, cld, trunc, round, sign, signbit
import Base: isless, isapprox, isinteger, isreal, isinf, isfinite
import Base: prevfloat, nextfloat, maxintfloat, rat, step #, linspace
import Base: promote_op, promote_array_type, promote_rule, unsafe_getindex
import Base: length, float, start, done, next, last, one, zero, colon#, range
import Base: getindex, eltype, step, last, first, frexp
import Base: Rational, Complex, typemin, typemax
# import Base: steprange_last, unitrange_last

export baseunit
export dimension
export power
export tens
export unit, unitless
export @unit

export Quantity, NormalQuantity, TemperatureQuantity

"Map the x in 10^x to an SI prefix."
const prefixdict = Dict(
    -24 => "y",
    -21 => "z",
    -18 => "a",
    -15 => "f",
    -12 => "p",
    -9  => "n",
    -6  => "μ",     # tab-complete \mu, not option-m on a Mac!
    -3  => "m",
    -2  => "c",
    -1  => "d",
    0   => "",
    1   => "da",
    2   => "h",
    3   => "k",
    6   => "M",
    9   => "G",
    12  => "T",
    15  => "P",
    18  => "E",
    21  => "Z",
    24  => "Y"
)

### Type definitions ###

"""
```
immutable Dimension{D}
    power::Rational{Int}
    Dimension(p) = new(p)
    Dimension(t,p) = new(p)
end
```

Description of a dimension, like length, time, etc. and powers thereof.
The name of the dimension `D` is a symbol. A two-argument constructor ignores
the first argument for simplicity in the function `*(a0::Unitlike, a::Unitlike...)`.
"""
immutable Dimension{D}
    power::Rational{Int}
    Dimension(p) = new(p)
    Dimension(t,p) = new(p)
end

"""
```
immutable Unit{U}
    tens::Int
    power::Rational{Int}
end
```

Description of a physical unit, including powers-of-ten prefixes and powers of
the unit. The name of the unit `U` is a symbol.
"""
immutable Unit{U}
    tens::Int
    power::Rational{Int}
end

"""
```
abstract Unitlike
```

Abstract container type for units or dimensions, which need similar manipulations
for collecting powers, sorting, canceling, etc.
"""
abstract Unitlike

immutable Units{N} <: Unitlike end
immutable Dimensions{N} <: Unitlike end

"""
```
abstract Quantity{T<:Number,D,U} <: Number
```

A physical quantity, which is dimensionful and has units.
"""
abstract Quantity{T<:Number,D,U} <: Number

"""
```
immutable NormalQuantity{T,D,U} <: Quantity{T,D,U}
    val::T
end
```

A quantity which may be converted to other quantities of the same dimension
by a rescaling. This is how most quantities behave (mass, length, time).
"""
immutable NormalQuantity{T,D,U} <: Quantity{T,D,U}
    val::T
end

"""
```
immutable TemperatureQuantity{T,D,U} <: Quantity{T,D,U}
    val::T
end
```

A temperature scale, which may be converted to other temperature scales
by a linear transformation.
"""
immutable TemperatureQuantity{T,D,U} <: Quantity{T,D,U}
    val::T
end

"""
```
@generated function Quantity(x::Number, y::Units)
```

Constructor for quantities. This is a generated function to avoid determining
the dimensions of a given set of units each time a new quantity is made. Note
that a `NormalQuantity` is always returned unless the quantity has dimensions
of temperature.
"""
@generated function Quantity(x::Number, y::Units)
    u = y()
    d = dimension(u)
    T = isa(d, Dimensions{(Dimension{:Temperature}(1),)}) ?
        TemperatureQuantity : NormalQuantity
    :(($T){typeof(x), typeof($d), typeof($u)}(x))
end

"""
```
abbr(x)
```

Display abbreviation for units or dimensions. Defaults to "???".
"""
abbr(x) = "???"     # Indicate missing abbreviations

"""
```
basefactor(x)
```

Specifies conversion factors to base SI units.
It returns a tuple. The first value is any irrational part of the conversion,
and the second value is a rational component. This segregation permits exact
conversions within unit systems that have no rational conversion to SI.
"""
function basefactor end

"""
```
macro dimension(name, abbr)
```

Extends `Unitful.abbr` and creates a type alias for the new dimension.
"""
macro dimension(name, abbr)
    x = Expr(:quote, name)
    esc(quote
        Unitful.abbr(::Unitful.Dimension{$x}) = $abbr
        typealias $(name){T,U}
            Quantity{T,Unitful.Dimensions{(Unitful.Dimension{$x}(1),)},U}
        export $(name)
    end)
end

"""
```
macro derived_dimension(dimension, derived...)
```

Creates type aliases for derived dimensions, like `[Area] = [Length]^2`.
"""
macro derived_dimension(dimension, tup)
    esc(quote
        typealias ($dimension){T,U}
            Quantity{T,Unitful.Dimensions{$tup},U}
        export $(dimension)
    end)
end

"""
```
macro prefixed_unit_symbols(sym, unit)
```

Given a unit abbreviation and a `Units` object, will define and export
units for each possible SI prefix on that unit.

e.g. nm, cm, m, km, ... all get defined when `@uall m _Meter` is typed.
"""
macro prefixed_unit_symbols(x,y)
    expr = Expr(:block)

    z = Expr(:quote, y)
    for (k,v) in prefixdict
        s = Symbol(v,x)
        ea = esc(quote
            const $s = Unitful.Units{(Unitful.Unit{$z}($k,1//1),)}()
            export $s
        end)
        push!(expr.args, ea)
    end

    expr
end

"""
Given a unit abbreviation and a `Units` object, will define and export
`UnitDatum`, without prefixes.

e.g. ft gets defined but not kft when `@u ft _Foot` is typed.
"""
macro unit_symbols(x,y)
    s = Symbol(x)
    z = Expr(:quote, y)
    esc(quote
        const $s = Unitful.Units{(Unitful.Unit{$z}(0,1//1),)}()
        export $s
    end)
end

@generated function tscale(x::Units)
    u = x()
    d = dimension(u)
    return isa(d, Dimensions{Dimension{:Temperature}(1)}) ?
        :(true) : :(false)
end

offsettemp{T}(::Type{Val{T}}) = 0

"""
```
macro baseunit(symb, name, abbr, dimension)
```

Define a base unit, typically but not necessarily SI. `symb` is t
"""
macro baseunit(symb, abbr, name, dimension)
    x = Expr(:quote, name)
    quote
        Unitful.abbr(::Unitful.Unit{$x}) = $abbr
        Unitful.dimension(y::Unitful.Unit{$x}) =
            ($dimension).body.parameters[2]()^y.power
        Unitful.basefactor(::Unitful.Unit{$x}) = (1.0, 1)
        Unitful.@prefixed_unit_symbols $symb $name
    end
end

macro unit(symb,abbr,name,equals,tf)
    # name is a symbol
    # abbr is a string
    x = Expr(:quote, name)
    quote
        inex, ex = Unitful.basefactor(Unitful.unit($equals))
        eq = Unitful.unitless($equals)
        Base.isa(eq, Base.Integer) || Base.isa(eq, Base.Rational) ?
             (ex *= eq) : (inex *= eq)
        Unitful.abbr(::Unitful.Unit{$x}) = $abbr
        Unitful.dimension(::Unitful.Unit{$x}) =
            Unitful.dimension($equals)
        Unitful.basefactor(::Unitful.Unit{$x}) = (inex, ex)
        if $tf
            Unitful.@prefixed_unit_symbols $symb $name
        else
            Unitful.@unit_symbols $symb $name
        end
    end
end

"""
`dimension(x)` specifies a `Dict` containing how many powers of each
dimension correspond to a given unit. It should be implemented for all units.
"""
function dimension end

@inline unitless(x::Quantity) = x.val

unit{S}(x::Unit{S}) = S
unit{S}(x::Dimension{S}) = S

tens(x::Unit) = x.tens
tens(x::Dimension) = 0

power(x::Unit) = x.power
power(x::Dimension) = x.power

unit{T,D,U}(x::Quantity{T,D,U}) = U()
unit{T,D,U}(x::Type{Quantity{T,D,U}}) = U()

quantity_type_symbols = (:NormalQuantity, :TemperatureQuantity)

"""
```
basefactor(x::Unit)
```

Powers of ten are not included for overflow reasons. See `tensfactor`
"""
function basefactor(x::Unit)
    inex, ex = basefactor(x)
    p = power(x)
    if isinteger(p)
        p = Integer(p)
    end

    can_exact = (ex < typemax(Int))
    can_exact &= (1/ex < typemax(Int))

    ex2 = float(ex)^p
    can_exact &= (ex2 < typemax(Int))
    can_exact &= (1/ex2 < typemax(Int))
    can_exact &= isinteger(p)

    if can_exact
        (inex^p, (ex//1)^p)
    else
        ((inex * ex)^p, 1)
    end
end

"""
```
basefactor(x::Units)
```

Calls `basefactor` on each of the `Unit` objects and multiplies together.
Needs some overflow checking?
"""
@generated function basefactor(x::Units)
    tunits = x.parameters[1]
    fact1 = map(basefactor, tunits)
    inex1 = mapreduce(x->getfield(x,1), *, fact1)
    ex1   = mapreduce(x->getfield(x,2), *, fact1)
    :(($inex1,$ex1))
end

function tensfactor(x::Unit)
    p = power(x)
    if isinteger(p)
        p = Integer(p)
    end
    abc = (x == kg ? 3 : 0)
    tens(x)*p - abc
end

"""
Unnecessary generated function to make the code easy to maintain.
"""
@generated function prefix(x::Val)
    if haskey(prefixdict, x.parameters[1])
        str = prefixdict[x.parameters[1]]
        :($str)
    else
        :(error("Invalid prefix"))
    end
end

# Addition / subtraction
for op in [:+, :-]

    @eval ($op){S,T,D,U}(x::Quantity{S,D,U}, y::Quantity{T,D,U}) =
        Quantity(($op)(x.val,y.val), U())

    # If not generated, there are run-time allocations
    @eval @generated function ($op){S,T,D,SU,TU}(x::Quantity{S,D,SU},
            y::Quantity{T,D,TU})
        result_units = SU + TU
        :($($op)(convert($result_units, x), convert($result_units, y)))
    end

    @eval ($op)(x::Quantity) = Quantity(($op)(x.val),unit(x))
end

# for x in quantity_type_symbols, y in quantity_type_symbols
#     @eval @generated function promote_op{S,SU,T,TU}(op,
#     ::Type{$x{S,SU}}, ::Type{$y{T,TU}})
#
#         numtype = promote_op(op(), S, T)
#         quant = numtype <: AbstractFloat ? FloatQuantity : RealQuantity
#         resunits = typeof(op()(SU(), TU()))
#         :(($quant){$numtype, $resunits})
#     end
# end

# Multiplication
# *{T<:Units}(x::Bool, y::T) = Quantity(x,y)

"Construct a unitful quantity by multiplication."
*(x::Real, y::Units, z::Units...) = Quantity(x,*(y,z...))

"Kind of weird but okay, sure"
*(x::Units, y::Real) = *(y,x)

"""
Given however many unit-like objects, multiply them together. The following
applies equally well to `Dimensions` instead of `Units`.

Collect `UnitDatum` from the types of the `Units` objects. For identical
units including SI prefixes (i.e. cm ≠ m), collect powers and sort uniquely.
The unique sorting permits easy unit comparisons.

It is likely that some compile-time optimization would be good...
"""
@generated function *(a0::Unitlike, a::Unitlike...)

    # Sort the units uniquely. This is a generated function so we
    # have access to the types of the arguments, not the values!

    D = (issubtype(a0,Units) ? Unit : Dimension)
    b = Array{D,1}()
    a0p = a0.parameters[1]
    length(a0p) > 0 && append!(b, a0p)
    for x in a
        xp = x.parameters[1]
        length(xp) > 0 && append!(b, xp)
    end

    sort!(b, by=x->power(x))
    D == Unit && sort!(b, by=x->tens(x))
    sort!(b, by=x->unit(x))

    # Units(m,m,cm,cm^2,cm^3,nm,m^4,µs,µs^2,s)
    # ordered as:
    # nm cm cm^2 cm^3 m m m^4 µs µs^2 s

    # Collect powers of a given unit
    c = Array{D,1}()
    i = start(b)
    oldstate = b[i]
    p=0//1
    while !done(b, i)
        (state, i) = next(b, i)
        if tens(state) == tens(oldstate) && unit(state) == unit(oldstate)
            p += power(state)
        else
            if p != 0
                push!(c, D{unit(oldstate)}(tens(oldstate),p))
            end
            p = power(state)
        end
        oldstate = state
    end
    if p != 0
        push!(c, D{unit(oldstate)}(tens(oldstate),p))
    end
    # results in:
    # nm cm^6 m^6 µs^3 s

    d = (c...)
    T = (issubtype(a0,Units) ? Units : Dimensions)
    :(($T){$d}())
end

@generated function *{T,D,U}(x::Quantity{T,D,U}, y::Units, z::Units...)
    result_units = *(U(),y(),map(x->x(),z)...)
    if isa(result_units,Units{()})
        :(x.val)
    else
        :(Quantity(x.val,$result_units))
    end
end


@generated function *(x::Quantity, y::Quantity)
    xunits = x.parameters[3]()
    yunits = y.parameters[3]()
    result_units = xunits*yunits
    quote
        z = x.val*y.val
        Quantity(z,$result_units)
    end
end

# Next two lines resolves some method ambiguity:
*{T<:Quantity}(x::Bool, y::T) =
    ifelse(x, y, ifelse(signbit(y), -zero(y), zero(y)))
*(x::Quantity, y::Bool) = Quantity(x.val*y, unit(x))

*(y::Real, x::Quantity) = *(x,y)
*(x::Quantity, y::Real) = Quantity(x.val*y, unit(x))

# function *(x::Complex, y::Units)
#     a,b = reim(x)
#     Complex(a*y,b*y)
# end
#
# function *(y::Units, x::Complex)
#     a,b = reim(x)
#     Complex(a*y,b*y)
# end
#
# "Necessary to enable expressions like Complex(1V,1mV)."
# @generated function Complex{S,T,U,V}(x::Quantity{S,T}, y::Quantity{U,V})
#     resulttype = typeof(x(1)+y(1))
#     :(Complex{$resulttype}(convert($resulttype,x),convert($resulttype,y)))
# end

for a in quantity_type_symbols
    @eval begin
        # number, quantity
        @generated function promote_op{R<:Real,S,D,U}(op,
            ::Type{R}, ::Type{($a){S,D,U}})

            numtype = promote_op(op(),R,S)
            unittype = typeof(op()(Units{()}(), U()))
            dimtype = typeof(dimension(unittype()))
            :(Quantity{$numtype, $dimtype, $unittype})
        end

        # quantity, number
        @generated function promote_op{R<:Real,S,SU}(op,
            ::Type{($a){S,SU}}, ::Type{R})

            numtype = promote_op(op(),S,R)
            unittype = typeof(op()(SU(), Units{()}()))
            dimtype = typeof(dimension(unittype()))
            :(Quantity{$numtype, $dimtype, $unittype})
        end

        # unit, quantity
        @generated function promote_op{R<:Units,S,SU}(op,
            ::Type{($a){S,SU}}, ::Type{R})

            numtype = S
            unittype = typeof(op()(SU(), R()))
            dimtype = typeof(dimension(unittype()))
            :(Quantity{$numtype, $dimtype, $unittype})
        end

        # quantity, unit
        @generated function promote_op{R<:Units,S,SU}(op,
            ::Type{R}, ::Type{($a){S,SU}})

            numtype = promote_op(op(),one(S),S)
            unittype = typeof(op()(R(), SU()))
            dimtype = typeof(dimension(unittype()))
            :(Quantity{$numtype, $dimtype, $unittype})
        end
    end
end

@eval begin
    @generated function promote_op{R<:Real,S<:Units}(op,
        x::Type{R}, y::Type{S})
        unittype = typeof(op()(Units{()}(), S()))
        dimtype = typeof(dimension(unittype()))
        :(Quantity{x, $dimtype, $unittype})
    end

    @generated function promote_op{R<:Real,S<:Units}(op,
        y::Type{S}, x::Type{R})
        unittype = typeof(op()(S(), Units{()}()))
        dimtype = typeof(dimension(unittype()))
        :(Quantity{x, $dimtype, $unittype})
    end
end

# See operators.jl
# Element-wise operations with units
for (f,F) in [(:./, :/), (:.*, :*), (:.+, :+), (:.-, :-)]
    @eval ($f)(x::Units, y::Units) = ($F)(x,y)
    @eval ($f)(x::Number, y::Units)   = ($F)(x,y)
    @eval ($f)(x::Units, y::Number)   = ($F)(x,y)
end
.\(x::Units, y::Units) = y./x
.\(x::Number, y::Units)   = y./x
.\(x::Units, y::Number)   = y./x

# See arraymath.jl
./(x::Units, Y::AbstractArray) =
    reshape([ x ./ y for y in Y ], size(Y))
./(X::AbstractArray, y::Units) =
    reshape([ x ./ y for x in X ], size(X))
.\(x::Units, Y::AbstractArray) =
    reshape([ x .\ y for y in Y ], size(Y))
.\(X::AbstractArray, y::Units) =
    reshape([ x .\ y for x in X ], size(X))

for f in (:.*,)
    @eval begin
        function ($f){T}(A::Units, B::AbstractArray{T})
            F = similar(B, promote_op($f,typeof(A),typeof(B)))
            for (iF, iB) in zip(eachindex(F), eachindex(B))
                @inbounds F[iF] = ($f)(A, B[iB])
            end
            return F
        end
        function ($f){T}(A::AbstractArray{T}, B::Units)
            F = similar(A, promote_op($f,typeof(A),typeof(B)))
            for (iF, iA) in zip(eachindex(F), eachindex(A))
                @inbounds F[iF] = ($f)(A[iA], B)
            end
            return F
        end
    end
end

# Division (floating point)

/(x::Units, y::Units)       = *(x,inv(y))
/(x::Real, y::Units)           = Quantity(x,inv(y))
/(x::Units, y::Real)           = (1/y) * x
/(x::Quantity, y::Units)       = Quantity(x.val, unit(x) / y)
/(x::Quantity, y::Quantity)       = Quantity(x.val / y.val, unit(x) / unit(y))
/(x::Quantity, y::Real)           = Quantity(x.val / y, unit(x))
/(x::Real, y::Quantity)           = Quantity(x / y.val, inv(unit(y)))

# Division (rationals)

//(x::Units, y::Units) = x/y
//(x::Real, y::Units)   = Rational(x)/y
//(x::Units, y::Real)   = (1//y) * x

//(x::Units, y::Quantity) = Quantity(1//y.val, x / unit(y))
//(x::Quantity, y::Units) = Quantity(x.val, unit(x) / y)
//(x::Quantity, y::Quantity) = Quantity(x.val // y.val, unit(x) / unit(y))

//(x::Quantity, y::Real) = Quantity(x.val // y, unit(x))
//(x::Real, y::Quantity) = Quantity(x // y.val, inv(unit(y)))

# Division (other functions)

for f in (:div, :fld, :cld)
    @eval function ($f)(x::Quantity, y::Quantity)
        z = convert(unit(y), x)
        ($f)(z.val,y.val)
    end
end

for f in (:mod, :rem)
    @eval function ($f)(x::Quantity, y::Quantity)
        z = convert(unit(y), x)
        Quantity(($f)(z.val,y.val), unit(y))
    end
end

# Exponentiation is not type stable.
# For now we define a special `inv` method to at least
# enable division to be fast.

"Fast inverse units."
@generated function inv(x::Units)
    tup = x.parameters[1]
    length(tup) == 0 && return :(x)
    tup2 = map(x->x^-1,tup)
    y = *(Units{tup2}())
    :($y)
end

^{T}(x::Unit{T}, y::Integer) = Unit{T}(tens(x),power(x)*y)
^{T}(x::Unit{T}, y) = Unit{T}(tens(x),power(x)*y)

^{T}(x::Dimension{T}, y::Integer) = Dimension{T}(power(x)*y)
^{T}(x::Dimension{T}, y) = Dimension{T}(power(x)*y)

for z in (:Units, :Dimensions)
    @eval begin
        function ^{T}(x::$z{T}, y::Integer)
            *($z{map(a->a^y, T)}())
        end

        function ^{T}(x::$z{T}, y)
            *($z{map(a->a^y, T)}())
        end
    end
end

^{T,D,U}(x::Quantity{T,D,U}, y::Integer) = Quantity((x.val)^y, U()^y)
^{T,D,U}(x::Quantity{T,D,U}, y::Rational) = Quantity((x.val)^y, U()^y)
^{T,D,U}(x::Quantity{T,D,U}, y::Real) = Quantity((x.val)^y, U()^y)

# Other mathematical functions
"Fast square root for units."
@generated function sqrt(x::Units)
    tup = x.parameters[1]
    tup2 = map(x->x^(1//2),tup)
    y = *(Units{tup2}())
    :($y)
end


for (f, F) in [(:min, :<), (:max, :>)]
    @eval @generated function ($f)(x::Quantity, y::Quantity)
        xdim = x.parameters[2]()
        ydim = y.parameters[2]()
        if xdim != ydim
            return :(error("Dimensional mismatch."))
        end

        xunits = x.parameters[3].parameters[1]
        yunits = y.parameters[3].parameters[1]

        factx = mapreduce(.*, xunits) do x
            vcat(basefactor(x)...)
        end
        facty = mapreduce(.*, yunits) do x
            vcat(basefactor(x)...)
        end

        tensx = mapreduce(tensfactor, +, xunits)
        tensy = mapreduce(tensfactor, +, yunits)

        convx = *(factx..., (10.0)^tensx)
        convy = *(facty..., (10.0)^tensy)

        :($($F)(x.val*$convx, y.val*$convy) ? x : y)
    end

    @eval ($f)(x::Units, y::Units) =
        unit(($f)(Quantity(1.0, x), Quantity(1.0, y)))
end

sqrt(x::Quantity) = Quantity(sqrt(x.val), sqrt(unit(x)))
abs(x::Quantity) = Quantity(abs(x.val),  unit(x))

trunc(x::Quantity) = Quantity(trunc(x.val), unit(x))
round(x::Quantity) = Quantity(round(x.val), unit(x))

isless{T,D,U}(x::Quantity{T,D,U}, y::Quantity{T,D,U}) = isless(x.val, y.val)
isless(x::Quantity, y::Quantity) = isless(convert(unit(y), x).val,y.val)
<{T,D,U}(x::Quantity{T,D,U}, y::Quantity{T,D,U}) = (x.val < y.val)
<(x::Quantity, y::Quantity) = <(convert(unit(y), x).val,y.val)

isapprox{T,D,U}(x::Quantity{T,D,U}, y::Quantity{T,D,U}) = isapprox(x.val, y.val)
isapprox(x::Quantity, y::Quantity) = isapprox(convert(unit(y), x).val, y.val)

=={S,T,D,U}(x::Quantity{S,D,U}, y::Quantity{T,D,U}) = (x.val == y.val)
function ==(x::Quantity, y::Quantity)
    dimension(x) != dimension(y) && return false
    convert(unit(y), x).val == y.val
end
==(x::Quantity, y::Complex) = false
==(x::Quantity, y::Irrational) = false
==(x::Quantity, y::Number) = false
==(y::Complex, x::Quantity) = false
==(y::Irrational, x::Quantity) = false
==(y::Number, x::Quantity) = false
<=(x::Quantity, y::Quantity) = <(x,y) || x==y

for f in (:zero, :floor, :ceil)
    @eval ($f)(x::Quantity) = Quantity(($f)(x.val), unit(x))
end

one(x::Quantity) = one(x.val)
one{T,D,U}(x::Type{NormalQuantity{T,D,U}}) = one(T)
one{T,D,U}(x::Type{TemperatureQuantity{T,D,U}}) = one(T)

isinteger(x::Quantity) = isinteger(x.val)
isreal(x::Quantity) = isreal(x.val)
isfinite(x::Quantity) = isfinite(x.val)
isinf(x::Quantity) = isinf(x.val)

sign(x::Quantity) = sign(x.val)
signbit(x::Quantity) = signbit(x.val)

"""
```
prevfloat{T<:AbstractFloat,D,U}(x::Quantity{T,D,U})
```

Like `prevfloat` for `AbstractFloat` types, but preserves units.
"""
prevfloat{T<:AbstractFloat,D,U}(x::Quantity{T,D,U}) =
    Quantity(prevfloat(x.val), unit(x))

"""
```
nextfloat{T<:AbstractFloat,D,U}(x::Quantity{T,D,U})
```

Like `nextfloat` for `AbstractFloat` types, but preserves units.
"""
nextfloat{T<:AbstractFloat,D,U}(x::Quantity{T,D,U}) =
    Quantity(nextfloat(x.val), unit(x))

"""
`frexp{T<:AbstractFloat,D,U}(x::Quantity{T,D,U})`

Same as for a unitless `AbstractFloat`, but the first number in the
result carries the units of the input.
"""
function frexp{T<:AbstractFloat,D,U}(x::Quantity{T,D,U})
    a,b = frexp(x.val)
    a *= unit(x)
    a,b
end

colon(start::Quantity, step::Quantity, stop::Quantity) =
    StepRange(promote(start, step, stop)...)

function Base.steprange_last{T<:Quantity}(start::T, step, stop)
    z = zero(step)
    step == z && throw(ArgumentError("step cannot be zero"))
    if stop == start
        last = stop
    else
        if (step > z) != (stop > start)
            last = start - step
        else
            diff = stop - start
            if T<:Signed && (diff > zero(diff)) != (stop > start)
                # handle overflowed subtraction with unsigned rem
                if diff > zero(diff)
                    remain = -convert(T, unsigned(-diff) % step)
                else
                    remain = convert(T, unsigned(diff) % step)
                end
            else
                remain = Base.steprem(start,stop,step)
            end
            last = stop - remain
        end
    end
    last
end

"""
Merge the keys of two dictionaries, adding the values if the keys were shared.
The first argument is modified.
"""
function mergeadd!(a::Dict, b::Dict)
    for (k,v) in b
        !haskey(a,k) ? (a[k] = v) : (a[k] += v)
    end
end

function dimension(x::Number)
    Units{()}()
end

function dimension(u::Unit)
    dims = dimension(Val{unit(u)})
    for (k,v) in dims
        dims[k] *= power(u)
    end
    t = [Dimension(k,v) for (k,v) in dims]
    *(Dimensions{(t...)}())
end

dimension{N}(u::Units{N}) = mapreduce(dimension, *, N)
dimension{T,D,U}(x::Quantity{T,D,U}) = D()

include("Display.jl")

"Forward numeric promotion wherever appropriate."
promote_rule{S,T,D,U}(::Type{Quantity{S,D,U}},::Type{Quantity{T,D,U}}) =
    Quantity{promote_type(S,T),D,U}

"""
Convert a unitful quantity to different units.

Is a generated function to allow for special casing, e.g. temperature conversion
"""
@generated function convert(a::Units, x::TemperatureQuantity)
    xunits = x.parameters[3]
    aData = a()
    xData = xunits()
    conv = convert(aData, xData)

    tup0 = xunits.parameters[1]
    tup1 = a.parameters[1]
    t0 = offsettemp(Val{unit(tup0[1])})
    t1 = offsettemp(Val{unit(tup1[1])})
    quote
        v = ((x.val + $t0) * $conv) - $t1
        Quantity(v, a)
    end
end

@generated function convert(a::Units, x::NormalQuantity)
    xunits = x.parameters[3]
    aData = a()
    xData = xunits()
    conv = convert(aData, xData)

    quote
        v = x.val * $conv
        Quantity(v, a)
    end
end

"""
Find the conversion factor from unit `t` to unit `s`, e.g.
`convert(m,cm) = 0.01`.
"""
@generated function convert(s::Units, t::Units)
    sunits = s.parameters[1]
    tunits = t.parameters[1]

    # Check if conversion is possible in principle
    sdim = dimension(s())
    tdim = dimension(t())
    sdim != tdim && error("Dimensional mismatch.")

    # first convert to base SI units.
    # fact1 is what would need to be multiplied to get to base SI units
    # fact2 is what would be multiplied to get from the result to base SI units

    inex1, ex1 = basefactor(t())
    inex2, ex2 = basefactor(s())

    a = inex1 / inex2
    ex = ex1 // ex2     # do overflow checking?

    tens1 = mapreduce(+,tunits) do x
        tensfactor(x)
    end
    tens2 = mapreduce(+,sunits) do x
        tensfactor(x)
    end
    pow = tens1-tens2

    fpow = 10.0^pow
    if fpow > typemax(Int) || 1/(fpow) > typemax(Int)
        a *= fpow
    else
        comp = (pow > 0 ? fpow * num(ex) : 1/fpow * den(ex))
        if comp > typemax(Int)
            a *= fpow
        else
            ex *= (10//1)^pow
        end
    end

    a ≈ 1.0 ? (inex = 1) : (inex = a)
    y = inex * ex
    :($y)
end

float(x::Quantity) = Quantity(float(x.val), unit(x))
Integer(x::Quantity) = Quantity(Integer(x.val), unit(x))
Rational(x::Quantity) = Quantity(Rational(x.val), unit(x))

"No conversion factor needed if you already have the right units."
convert{S}(s::Units{S}, t::Units{S}) = 1

"Needed to avoid complaints about ambiguous methods"
convert(::Type{Bool}, x::Quantity)    = Bool(x.val)
"Needed to avoid complaints about ambiguous methods"
convert(::Type{Integer}, x::Quantity) = Integer(x.val)
"Needed to avoid complaints about ambiguous methods"
convert(::Type{Complex}, x::Quantity) = Complex(x.val,0)

"Strip units from a number."
convert{S<:Number}(::Type{S}, x::Quantity) = convert(S, x.val)

include("Defaults.jl")

end
