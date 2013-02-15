(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

(** {2 Persistent Knowledge Base} *)

type t

val empty : t

val add_item : t -> Pattern.item -> t

val to_seq : t -> Pattern.item Sequence.t
val of_seq : t -> Pattern.item Sequence.t -> t

val to_json : t -> json
val of_json : t -> json -> t

val pp : Format.formatter -> t -> unit

(** {2 Saving/restoring KB from disk} *)

val save : file:string -> t -> unit

val restore : file:string -> t -> t