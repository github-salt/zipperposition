
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Positions in terms, clauses...} *)

(** A position is a path in a tree *)
type t =
  | Stop
  | Type of t (** Switch to type *)
  | Record_field of string * t (** Field of a record *)
  | Head of t (** Head of uncurried term *)
  | Arg of int * t (** argument term in uncurried term, or in multiset *)
  | Body of t (** Body of binder *)

type position = t

let stop = Stop
let type_ pos = Type pos
let record_field name pos = Record_field (name, pos)
let head pos = Head pos
let arg i pos = Arg (i, pos)
let body pos = Body pos

let compare = Pervasives.compare
let eq p1 p2 = compare p1 p2 = 0
let hash p = Hashtbl.hash p

let rev pos =
  let rec aux acc pos = match pos with
    | Stop -> acc
    | Type pos' -> aux (Type acc) pos'
    | Record_field (n,pos') -> aux (Record_field (n,acc)) pos'
    | Head pos' -> aux (Head acc) pos'
    | Arg (i, pos') -> aux (Arg (i,acc)) pos'
    | Body pos' -> aux (Body acc) pos'
  in
  aux Stop pos

(* Recursive append *)
let rec append p1 p2 = match p1 with
  | Stop -> p2
  | Type p1' -> Type (append p1' p2)
  | Record_field(name, p1') -> Record_field(name,append p1' p2)
  | Head p1' -> Head (append p1' p2)
  | Arg(i, p1') -> Arg (i,append p1' p2)
  | Body p1' -> Body (append p1' p2)

let rec pp out pos = match pos with
  | Stop -> CCFormat.string out "ε"
  | Type p' -> CCFormat.string out "τ."; pp out p'
  | Record_field (name,p') ->
      Format.fprintf out "{%s}." name; pp out p'
  | Head p' -> CCFormat.string out "@."; pp out p'
  | Arg (i,p') -> Format.fprintf out "%d." i; pp out p'
  | Body p' -> Format.fprintf out "β."; pp out p'

let to_string = CCFormat.to_string pp

(** {2 Position builder}

    We use an adaptation of difference lists for this tasks *)

module Build = struct
  type t =
    | E (** Empty (identity function) *)
    | P of position * t (** Pre-pend given position, then apply previous builder *)
    | N of (position -> position) * t
    (** Apply function to position, then apply linked builder *)

  let empty = E

  let of_pos p = P (p, E)

  (* how to apply a difference list to a tail list *)
  let rec __apply tail b = match b with
    | E -> tail
    | P (pos0,b') -> __apply (append pos0 tail) b'
    | N (f, b') -> __apply (f tail) b'

  let to_pos b = __apply stop b

  let suffix b pos =
    (* given a suffix, first append pos to it, then apply b *)
    N ((fun pos0 -> append pos pos0), b)

  let prefix pos b =
    (* tricky: this doesn't follow the recursive structure. Hence we
        need to first apply b totally, then pre-prend pos *)
    N ((fun pos1 -> append pos (__apply pos1 b)), E)

  let type_ b = N (type_, b)
  let record_field n b = N (record_field n, b)
  let head b = N(head, b)
  let arg i b = N(arg i, b)
  let body b = N(body, b)

  let pp out t = pp out (to_pos t)
  let to_string t = to_string (to_pos t)
end
