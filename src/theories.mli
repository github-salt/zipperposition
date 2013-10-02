
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

(** {6 Specifications of Built-in Theories} *)

open Logtk

(** {2 Associativity-Commutativity} *)

module AC : sig
  type t = private {
    is_ac : Symbol.t -> bool;
    symbols : unit -> Symbol.SSet.t;
    add : Symbol.t -> unit;
  }

  val create : ?base:bool -> unit -> t
    (** Create a new specification. If [base] is true (default), then
        AC symbols from the default signature are declared (arithmetic...) *)

  val add : spec:t -> Symbol.t -> unit
    (** Add the symbol to the list of AC symbols *)

  val is_ac : spec:t -> Symbol.t -> bool
    (** Check whether the symbol is AC *)

  val symbols : spec:t -> Symbol.SSet.t
end

(** {2 Total Ordering} *)

module TotalOrder : sig
  type instance = {
    less : Symbol.t;
    lesseq : Symbol.t;
  } (** A single instance of total ordering *)

  type t 

  type lit = {
    left : Term.t;
    right : Term.t;
    strict : bool;
    instance : instance;
  } (** A literal is an atomic inequality. [strict] is [true] iff the
      literal is a strict inequality, and the ordering itself
      is also provided. *)

  val create : ?base:bool -> unit -> t
    (** New specification. It already contains an instance
        for "$less" and "$lesseq" if [base] is true (default). *)

  val add : spec:t -> less:Symbol.t -> lesseq:Symbol.t -> instance
    (** New instance of ordering.
        @raise Invalid_argument if one of the symbols is already part of an
              instance. *)

  val is_less : spec:t -> Symbol.t -> bool

  val is_lesseq : spec:t -> Symbol.t -> bool

  val find : spec:t -> Symbol.t -> instance
    (** Find the instance that corresponds to this symbol.
        @raise Not_found if the symbol is not part of any instance. *)

  val is_order_symbol : spec:t -> Symbol.t -> bool
    (** Is less or lesseq of some instance? *)

  val tstp_instance : spec:t -> instance
    (** The specific instance that complies with TSTP signature $less, $lesseq *)
end