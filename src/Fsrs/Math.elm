module Fsrs.Math exposing (exp)

{-| `Math.exp` for Elm, so that the FSRS port matches ts-fsrs bit for bit.

Elm has no `exp`; `e ^ x` compiles to `Math.pow(Math.E, x)`, which differs from
V8's `Math.exp` in the last bit for most arguments. This is a port of fdlibm
`e_exp.c` as adapted in V8 `src/base/ieee754.cc` (which implements V8's
`Math.exp`), using only double arithmetic: the high-word comparisons become
comparisons against the doubles with those high words, and scaling by 2^k uses
`Math.pow(2, k)`, which is exact. It matched V8's `Math.exp` on 5 million
random arguments; `tests/fixtures/fsrs/math-exp.json` holds test vectors.

fdlibm notice: Copyright (C) 1993-2004 by Sun Microsystems, Inc. All rights
reserved. Developed at SunSoft, a Sun Microsystems, Inc. business. Permission
to use, copy, modify, and distribute this software is freely granted, provided
that this notice is preserved.

@docs exp

-}


{-| fdlibm `__ieee754_exp` as in V8 `src/base/ieee754.cc`, matching V8's
`Math.exp` bit for bit. Thresholds are the doubles whose high words fdlibm
compares against (low word 0).
-}
exp : Float -> Float
exp x0 =
    let
        ax =
            abs x0

        neg =
            x0 < 0
    in
    if isNaN x0 then
        x0

    else if ax >= 709.7822265625 && x0 > 709.782712893384 then
        1 / 0

    else if ax >= 709.7822265625 && x0 < -745.1332191019411 then
        0

    else if ax < 0.3465735912322998 && ax < 3.725290298461914e-9 then
        1 + x0

    else if ax < 0.3465735912322998 then
        expReduced 0 0 x0 0

    else if ax < 1.0397205352783203 then
        if x0 == 1 then
            e

        else
            let
                ( hi, lo, k ) =
                    if neg then
                        ( x0 + ln2Hi, negate ln2Lo, -1 )

                    else
                        ( x0 - ln2Hi, ln2Lo, 1 )
            in
            expReduced hi lo (hi - lo) k

    else
        let
            k =
                truncate
                    (invLn2
                        * x0
                        + (if neg then
                            -0.5

                           else
                            0.5
                          )
                    )

            hi =
                x0 - toFloat k * ln2Hi

            lo =
                toFloat k * ln2Lo
        in
        expReduced hi lo (hi - lo) k


expReduced : Float -> Float -> Float -> Int -> Float
expReduced hi lo x k =
    let
        t =
            x * x

        c =
            x - t * (0.16666666666666602 + t * (-0.0027777777777015593 + t * (0.00006613756321437934 + t * (-0.0000016533902205465252 + t * 4.1381367970572385e-8))))
    in
    if k == 0 then
        1 - ((x * c) / (c - 2.0) - x)

    else
        let
            y =
                1 - ((lo - (x * c) / (2.0 - c)) - hi)
        in
        if k >= -1021 then
            if k == 1024 then
                y * 2.0 * (2 ^ 1023)

            else
                y * (2 ^ toFloat k)

        else
            y * (2 ^ toFloat (k + 1000)) * 9.332636185032189e-302


ln2Hi : Float
ln2Hi =
    0.6931471803691238


ln2Lo : Float
ln2Lo =
    1.9082149292705877e-10


invLn2 : Float
invLn2 =
    1.4426950408889634
