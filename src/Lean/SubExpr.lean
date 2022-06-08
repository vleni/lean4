/-
Copyright (c) 2021 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Sebastian Ullrich, Daniel Selsam, Wojciech Nawrocki, E.W.Ayers
-/
import Lean.Meta.Basic
import Lean.Data.Json
import Std.Data.RBMap

namespace Lean

/-- A position of a subexpression in an expression.

See docstring of `SubExpr` for more detail.-/
def SubExpr.Pos := Nat

namespace SubExpr.Pos

def maxChildren := 4

/-- The coordinate `3 = maxChildren - 1` is
reserved to denote the type of the expression. -/
def typeCoord : Nat := maxChildren - 1

def asNat : Pos → Nat := id

instance : Inhabited Pos := show Inhabited Nat by infer_instance
instance : Ord Pos := show Ord Nat by infer_instance
instance : FromJson Pos := show FromJson Nat by infer_instance
instance : ToJson Pos := show ToJson Nat by infer_instance
instance : Repr Pos := show Repr Nat by infer_instance
instance : ToString Pos := show ToString Nat by infer_instance

/-- The Pos representing the root subexpression. -/
def root : Pos := (1 : Nat)

def isRoot (p : Pos) : Bool := p.asNat == 1

/-- The coordinate deepest in the Pos. -/
def head (p : Pos) : Nat :=
  if p.isRoot then panic! "already at top"
  else p.asNat % maxChildren

def tail (p : Pos) : Pos :=
  if p.isRoot then panic! "already at top"
  else (p.asNat - p.head) / maxChildren

def push (p : Pos) (c : Nat) : Pos :=
  if c >= maxChildren then panic! s!"invalid coordinate {c}"
  else p.asNat * maxChildren + c

/-- `pushNZeros p count` runs `.push 0` `count` times. -/
def pushNZeros (p : Pos) (count : Nat) : Pos :=
  p.asNat * (maxChildren ^ count)

variable {α : Type} [Inhabited α]

/-- Fold over the position starting at the root and heading to the leaf-/
def foldl  (f : α → Nat → α) : α → Pos → α :=
  fix2 (fun r a p => if p.isRoot then a else f (r a p.tail) p.head)

/-- Fold over the position starting at the root and heading to the leaf-/
def foldr  (f : Nat → α → α) : Pos → α → α :=
  fix2 (fun r p a => if p.isRoot then a else r p.tail (f p.head a))

def foldrM [Monad M] (f : Nat → α → M α) : Pos → α → M α :=
  fix2 (fun r p a => if p.isRoot then pure a else f p.head a >>= r p.tail)

def depth (p : Pos) :=
  p.foldr (fun _ => Nat.succ) 0

/-- Returns true if `pred` is true for each coordinate in `p`.-/
def all (pred : Nat → Bool) (p : Pos) : Bool :=
  OptionT.run (m := Id) (foldrM (fun n a => if pred n then pure a else failure) p ()) |>.isSome

def append : Pos → Pos → Pos := foldl push

/-- Creates a subexpression `Pos` from an array of 'coordinates'.
Each coordinate is a number {0,1,2} expressing which child subexpression should be explored.
The first coordinate in the array corresponds to the root of the expression tree.  -/
def ofArray (ps : Array Nat) : Pos :=
  ps.foldl push root

/-- Decodes a subexpression `Pos` as a sequence of coordinates. See `Pos.fromArray` for details.-/
def toArray (p : Pos) : Array Nat :=
  foldl Array.push #[] p

def pushBindingDomain (p : Pos) := p.push 0
def pushBindingBody   (p : Pos) := p.push 1
def pushLetVarType    (p : Pos) := p.push 0
def pushLetValue      (p : Pos) := p.push 1
def pushLetBody       (p : Pos) := p.push 2
def pushAppFn         (p : Pos) := p.push 0
def pushAppArg        (p : Pos) := p.push 1
def pushProj          (p : Pos) := p.push 0

def pushNaryFn (numArgs : Nat) (p : Pos) : Pos :=
  p.asNat * (maxChildren ^ numArgs)
def pushNaryArg (numArgs argIdx : Nat) (p : Pos) : Pos :=
  show Nat from p.asNat * (maxChildren ^ (numArgs - argIdx)) + 1

end SubExpr.Pos

/-- An expression and the position of a subexpression within this expression.

Subexpressions are encoded as the current subexpression `e` and a
position `p : Pos` denoting `e`'s position with respect to the root expression.

We use a simple encoding scheme for expression positions `Pos`:
every `Expr` constructor has at most 3 direct expression children. Considering an expression's type
to be one extra child as well, we can injectively map a path of `childIdxs` to a natural number
by computing the value of the 4-ary representation `1 :: childIdxs`, since n-ary representations
without leading zeros are unique. Note that `pos` is initialized to `1` (case `childIdxs == []`).-/
structure SubExpr where
  expr : Expr
  pos  : SubExpr.Pos
  deriving Inhabited

namespace SubExpr

def mkRoot (e : Expr) : SubExpr := ⟨e, Pos.root⟩

/-- Returns true if the selected subexpression is the topmost one.-/
def isRoot (s : SubExpr) : Bool := s.pos.isRoot

def mapPos (f : Pos → Pos) : SubExpr → SubExpr
  | ⟨e,p⟩ => ⟨e, f p⟩

end SubExpr

open SubExpr in
/-- Same as `Expr.traverseApp` but also includes a
`SubExpr.Pos` argument for tracking subexpression position. -/
def Expr.traverseAppWithPos {M} [Monad M] (visit : Pos → Expr → M Expr) (p : Pos) (e : Expr) : M Expr :=
  match e with
  | Expr.app f a _ =>
    e.updateApp!
      <$> traverseAppWithPos visit p.pushAppFn f
      <*> visit p.pushAppArg a
  | e => visit p e

end Lean
