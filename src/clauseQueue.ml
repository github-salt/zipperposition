
(*
Zipperposition: a functional superposition prover for prototyping
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Priority Queue of clauses} *)

(** Heuristic selection of clauses, using queues. Note that some
    queues do not need accept all clauses, as long as one of them does
    (for completeness). Anyway, a fifo queue should always be present,
    and presents this property. *)

open Logtk

module O = Ordering
module Lit = Literal
module Lits = Literals

(** {2 A priority queue of clauses, purely functional} *)
module type S = sig
  module C : Clause.S

  type t

  val add : t -> C.t -> t
    (** Add a clause to the Queue *)

  val adds : t -> C.t Sequence.t -> t
    (** Add clauses to the queue *)

  val is_empty : t -> bool
    (** check whether the queue is empty *)

  val take_first : t -> (t * C.t)
    (** Take first element of the queue, or raise Not_found *)

  val clean : t -> C.CSet.t -> t
    (** remove all clauses that are not in the set *)

  val name : t -> string
    (** Name of the implementation/role of the queue *)

  (** {6 Available Queues} *)

  val fifo : t
    (** select by increasing age (for fairness) *)

  val clause_weight : t
    (** select by increasing weight of clause *)

  val goals : t
    (** only select goals (clauses with only negative lits) *)

  val non_goals : t
    (** only select non-goals *)

  val ground : t
    (** only select ground clauses *)

  val pos_unit_clauses : t
    (** only select positive unit clauses *)

  val horn : t
    (** select horn clauses *)

  val lemmas : t
    (** only select lemmas *)

  val mk_queue : ?accept:(C.t -> bool) -> weight:(C.t -> int) -> string -> t
    (** Bring your own implementation of queue *)

  (** {6 Combination of queues} *)

  type queues = (t * int) list

  module Profiles : sig
    val bfs : queues
      (** Strong orientation toward FIFO *)

    val explore : queues
      (** Use heuristics for selecting "small" clauses *)

    val ground : queues
      (** Favor positive unit clauses and ground clauses *)
  end

  val default_queues : queues
    (** default combination of heuristics *)

  (** {6 IO} *)

  val pp : Buffer.t -> t -> unit
  val to_string : t -> string
  val pp_list : Buffer.t -> (t * int) list -> unit
  val fmt : Format.formatter -> t -> unit
end

let _profile = ref "default"
let profile () = !_profile
let set_profile s = _profile := s

let () =
  Params.add_opts
    [ "-clause-queue"
    , Arg.String set_profile
    , "choose which set of clause queues to use \
      (for selecting next active clause): choices: default,bfs,explore,ground"
    ]

module Make(C : Clause.S) = struct
  module C = C

  let empty_heap =
    let leq (i1, c1) (i2, c2) = i1 <= i2 || (i1 = i2 && C.id c1 <= C.id c2) in
    Leftistheap.empty_with ~leq

  type t = {
    heap : (int * C.t) Leftistheap.t;
    functions : functions;
  } (** A priority queue of clauses, purely functional *)
  and functions = {
    weight : C.t -> int;
    accept : C.t -> bool;
    name : string;
  }

  (** generic clause queue based on some ordering on clauses, given
      by a weight function *)
  let mk_queue ?(accept=(fun _ -> true)) ~weight name =
    let functions = {
      weight;
      accept;
      name;
    } in
    { heap = empty_heap; functions; }

  let is_empty q =
    Leftistheap.is_empty q.heap

  let add q c =
    if q.functions.accept c
      then
        let w = q.functions.weight c in
        let heap = Leftistheap.insert q.heap (w, c) in
        { q with heap; }
      else q

  let adds q hcs =
    let heap =
      Sequence.fold
        (fun heap c ->
          if q.functions.accept c
            then
              let w = q.functions.weight c in
              Leftistheap.insert heap (w,c)
            else heap)
        q.heap hcs in
    { q with heap; }

  let take_first q =
    (if is_empty q then raise Not_found);
    let new_h, (_, c) = Leftistheap.extract_min q.heap in
    let q' = { q with heap=new_h; } in
    q', c

  (** Keep only the clauses that are in the set *)
  let clean q set =
    let new_heap = Leftistheap.filter q.heap (fun (_, c) -> C.CSet.mem set c) in
    { q with heap=new_heap; }

  let name q = q.functions.name

  (* weight function, that estimates how "difficult" it is to get rid of
      the literals of the clause. In other words, by selecting the clause,
      how far we are from the empty clause. *)
  let _default_weight c =
    let w = Array.fold_left
      (fun acc lit -> acc + Lit.heuristic_weight lit)
      0 (C.lits c)
    in w * Array.length (C.lits c)

  let fifo =
    let name = "fifo_queue" in
    mk_queue ~weight:(fun c -> C.id c) name

  let clause_weight =
    let name = "clause_weight" in
    mk_queue ~weight:_default_weight name

  let goals =
    (* check whether a literal is a goal *)
    let is_goal_lit lit = Lit.is_neg lit in
    let is_goal_clause c = Util.array_forall is_goal_lit (C.lits c) in
    let name = "prefer_goals" in
    mk_queue ~accept:is_goal_clause ~weight:_default_weight name

  let ground =
    let name = "prefer_ground" in
    mk_queue ~accept:C.is_ground ~weight:_default_weight name

  let non_goals =
    (* check whether a literal is a goal *)
    let is_goal_lit lit = Lit.is_neg lit in
    let is_non_goal_clause c = Util.array_forall
      (fun x -> not (is_goal_lit x))
      (C.lits c) in
    let name = "prefer_non_goals" in
    mk_queue ~accept:is_non_goal_clause ~weight:_default_weight name

  let pos_unit_clauses =
    let is_unit_pos c = match C.lits c with
    | [| lit |] when Lit.is_pos lit -> true
    | _ -> false
    in
    let name = "prefer_pos_unit_clauses" in
    mk_queue ~accept:is_unit_pos ~weight:_default_weight name

  let horn =
    let accept c = Lits.is_horn (C.lits c) in
    let name = "prefer_horn" in
    mk_queue ~accept ~weight:_default_weight name

  let lemmas =
    let name = "lemmas" in
    let accept c = C.get_flag C.flag_lemma c in
    (* use a fifo on lemmas *)
    mk_queue ~accept ~weight:_default_weight name

  (** {6 Combination of queues} *)

  type queues = (t * int) list

  module Profiles = struct
    let bfs =
      [ fifo, 5
      ; clause_weight, 1
      ]

    let explore =
      [ fifo, 1
      ; clause_weight, 4
      ; goals, 1
      ]

    let ground =
      [ fifo, 1
      ; pos_unit_clauses, 1
      ; ground, 2
      ]
  end

  let default_queues =
    match !_profile with
    | "default" ->
        [ fifo, 4
        ; clause_weight, 3
        ; goals, 1
        ; pos_unit_clauses, 1
        ]
    | "bfs" -> Profiles.bfs
    | "explore" -> Profiles.explore
    | "ground" -> Profiles.ground
    | n -> failwith ("no such profile: " ^ n)

  let pp buf q =
    Printf.bprintf buf "queue %s" (name q)

  let to_string q =
    let buf = Buffer.create 15 in
    pp buf q;
    Buffer.contents buf

  let pp_list buf qs =
    let pp_pair buf (c, i) = Printf.bprintf buf "%a (w=%d)" pp c i in
    Buffer.add_char buf '[';
    Util.pp_list pp_pair buf qs;
    Buffer.add_char buf ']';
    ()

  let fmt fmt q =
    Format.pp_print_string fmt (to_string q)
end
