Add LoadPath "..".
Require Import veric.base.
Require Import veric.Clight_lemmas.
Require Import veric.sim. (*forward_simulations.
Require Import veric.forward_simulations_proofs.*)

Inductive cont': Type :=
  | Kseq: statement -> cont'       (**r [Kseq s2 k] = after [s1] in [s1;s2] *)
  | Kfor2: expr -> statement -> statement -> cont'       (**r [Kfor2 e2 e3 s k] = after [s] in [for'(e2;e3) s] *)
  | Kfor3: expr -> statement -> statement  -> cont'       (**r [Kfor3 e2 e3 s k] = after [e3] in [for'(e2;e3) s] *)
  | Kswitch: cont'       (**r catches [break] statements arising out of [switch] *)
(*  | Kfun: fundef -> list val -> forall (l: option ident), cont' *)
  | Kcall: forall (l: option ident),                  (**r where to store result *)
           function ->                      (**r called (not calling!) function *)
           env ->                           (**r local env of calling function *)
           temp_env ->                      (**r temporary env of calling function *)
           cont'.
(*
   | Kreturn: val -> cont'.
*)

Definition cont := list cont'.

(** Pop continuation until a call or stop *)

Fixpoint call_cont (k: cont) : cont :=
  match k with
  | Kseq s :: k => call_cont k
  | Kfor2 e2 e3 s :: k => call_cont k
  | Kfor3 e2 e3 s :: k => call_cont k
  | Kswitch :: k => call_cont k
  | _ => k
  end.

Fixpoint current_function (k: cont) : option function :=
 match k with
  | Kseq s :: k => current_function k
  | Kfor2 e2 e3 s :: k => current_function k
  | Kfor3 e2 e3 s :: k =>current_function k
  | Kswitch :: k => current_function k
  | Kcall _ f _ _ :: _ => Some f
  | _ => None
  end.

Fixpoint continue_cont (k: cont) : cont :=
  match k with
  | Kseq s :: k' => continue_cont k'
  | Kfor2 e2 e3 s :: k' => Kseq e3 :: Kfor3 e2 e3 s :: k'
  | Kswitch :: k' => continue_cont k'
  | _ => nil (* stuck *)
  end.

Fixpoint precontinue_cont (k: cont) : cont :=
  match k with
  | Kseq s :: k' => precontinue_cont k'
  | Kfor2 _ _ _ :: _ => k
  | Kswitch :: k' => precontinue_cont k'
  | _ => nil (* stuck *)
  end.

Fixpoint break_cont (k: cont) : cont :=
  match k with
  | Kseq s :: k' => break_cont k'
  | Kfor2 e2 e3 s :: k' => k'
  | Kfor3 e2 e3 s :: _ => nil  (* stuck *)
  | Kswitch :: k' => k'
  | _ =>  nil (* stuck *)
  end.

Inductive corestate := 
 | State: forall (ve: env) (te: temp_env) (k: cont), corestate
 | ExtCall: forall (ef: external_function) (sig: signature) (args: list val) (lid: option ident) (ve: env) (te: temp_env) (k: cont),
                corestate.

Fixpoint strip_skip (k: cont) : cont :=
 match k with Kseq Sskip :: k' => strip_skip k' | _ => k end.

(*LENB: TYPE HAS CHANGED FROM option (external_function * signature * list val) 
   to  option (external_function  * list val) 
Definition cl_at_external (c: corestate) : option (external_function * signature * list val) :=
  match c with
  |  State _ _ k => None
  | ExtCall ef sig args lid ve te k => Some (ef, sig, args)
 end.*)
Definition cl_at_external (c: corestate) : option (external_function * list val) :=
  match c with
  |  State _ _ k => None
  | ExtCall ef sig args lid ve te k => Some (ef, args)
 end.

(*LENB: TYPE HAS CHANGED FROM  list val -> corestate -> option corestate
   to  val -> corestate -> option corestate
Definition cl_after_external (vret: val) (c: corestate) : option corestate :=
  match vret, c with
  | v, ExtCall ef sig args (Some id) ve te k => Some (State ve (PTree.set id v te) k)
  | v, ExtCall ef sig args None ve te k => Some (State ve te k)
  | _, _ => None
  end.*)
Definition cl_after_external (vret: val) (c: corestate) : option corestate :=
  match vret, c with
  | v, ExtCall ef sig args (Some id) ve te k => Some (State ve (PTree.set id v te) k)
  | v, ExtCall ef sig args None ve te k => Some (State ve te k)
  | _, _ => None
  end.

(** Find the statement and manufacture the continuation 
  corresponding to a label *)

Fixpoint find_label (lbl: label) (s: statement) (k: cont) 
                    {struct s}: option cont :=
  match s with
  | Ssequence s1 s2 =>
      match find_label lbl s1 (Kseq s2 :: k) with
      | Some sk => Some sk
      | None => find_label lbl s2 k
      end
  | Sifthenelse a s1 s2 =>
      match find_label lbl s1 k with
      | Some sk => Some sk
      | None => find_label lbl s2 k
      end
  | Swhile a s1 =>
      find_label lbl s1 (Kseq Scontinue :: Kfor2 a Sskip s1::  k)
  | Sdowhile a s1 =>
      find_label lbl s1 (Kseq Scontinue :: Kfor2 a Sskip s1 :: k)
  | Sfor' a2 a3 s1 =>
      match find_label lbl s1 (Kseq Scontinue :: Kfor2 a2 a3 s1 :: k) with
      | Some sk => Some sk
      | None => find_label lbl a3 (Kfor3 a2 a3 s1 :: k)
      end
  | Sswitch e sl =>
      find_label_ls lbl sl (Kswitch :: k)
  | Slabel lbl' s' =>
      if ident_eq lbl lbl' then Some(Kseq s' :: k) else find_label lbl s' k
  | _ => None
  end

with find_label_ls (lbl: label) (sl: labeled_statements) (k: cont) 
                    {struct sl}: option cont :=
  match sl with
  | LSdefault s => find_label lbl s k
  | LScase _ s sl' =>
      match find_label lbl s (Kseq (seq_of_labeled_statement sl') :: k) with
      | Some sk => Some sk
      | None => find_label_ls lbl sl' k
      end
  end.


(** Transition relation *)

Inductive cl_step (ge: Clight.genv): forall (q: corestate) (m: mem) (q': corestate) (m': mem), Prop :=

  | step_assign: forall ve te k m a1 a2 loc ofs v2 v t m',
     type_is_volatile (typeof a1) = false ->
      Clight_sem.eval_lvalue ge ve te m a1 loc ofs ->
      Clight_sem.eval_expr ge ve te m a2 v2 ->
      sem_cast v2 (typeof a2) (typeof a1) = Some v ->
      Csem.assign_loc ge (typeof a1) m loc ofs v t m' ->
      cl_step ge (State ve te (Kseq (Sassign a1 a2):: k)) m (State ve te k) m'

  | step_set:   forall ve te k m id a v,
      Clight_sem.eval_expr ge ve te m a v ->
      cl_step ge (State ve te (Kseq (Sset id a) :: k)) m (State ve (PTree.set id v te) k) m

  | step_call_internal:   forall ve te k m optid a al tyargs tyres vf vargs f m1 ve' le',
      classify_fun (typeof a) = fun_case_f tyargs tyres ->
      Clight_sem.eval_expr ge ve te m a vf ->
      Clight_sem.eval_exprlist ge ve te m al tyargs vargs ->
      Genv.find_funct ge vf = Some (Internal f) ->
      type_of_function f = Tfunction tyargs tyres ->
      list_norepet (var_names f.(fn_params) ++ var_names f.(fn_temps)) ->
      Csem.alloc_variables empty_env m (f.(fn_vars)) ve' m1 ->
      bind_parameter_temps f.(fn_params) vargs (create_undef_temps f.(fn_temps)) = Some 
le' ->
      cl_step ge (State ve te (Kseq (Scall optid a al) :: k)) m
                   (State ve' le' (Kseq f.(fn_body) :: Kseq (Sreturn None) :: Kcall optid f ve te :: k)) m1

  | step_call_external:   forall ve te k m optid a al tyargs tyres vf vargs ef,
      classify_fun (typeof a) = fun_case_f tyargs tyres ->
      Clight_sem.eval_expr ge ve te m a vf ->
      Clight_sem.eval_exprlist ge ve te m al tyargs vargs ->
      Genv.find_funct ge vf = Some (External ef tyargs tyres) ->
      cl_step ge (State ve te (Kseq (Scall optid a al) :: k)) m (ExtCall ef (signature_of_type tyargs tyres) vargs optid ve te k) m

  | step_seq: forall ve te k m s1 s2 st' m',
          cl_step ge (State ve te (Kseq s1 :: Kseq s2 :: k)) m st' m' ->
          cl_step ge (State ve te (Kseq (Ssequence s1 s2) :: k)) m st' m'

  | step_skip: forall ve te k m st' m',
          cl_step ge (State ve te k) m st' m' ->
          cl_step ge (State ve te (Kseq Sskip :: k)) m st' m'

  | step_continue: forall ve te k m st' m',
           cl_step ge (State ve te (continue_cont k)) m st' m' ->
           cl_step ge (State ve te (Kseq Scontinue :: k)) m st' m' 

  | step_break: forall ve te k m st' m',
                   cl_step ge (State ve te (break_cont k)) m st' m' ->
                   cl_step ge (State ve te (Kseq Sbreak :: k)) m st' m'

  | step_ifthenelse:  forall ve te k m a s1 s2 v1 b,
      Clight_sem.eval_expr ge ve te m a v1 ->
      bool_val v1 (typeof a) = Some b ->
      cl_step ge (State ve te (Kseq (Sifthenelse a s1 s2) :: k)) m (State ve te  (Kseq (if b then s1 else s2) :: k)) m

  | step_while: forall ve te k m a s st' m',
      cl_step ge (State ve te (Kseq (Sfor' a Sskip s) :: k)) m st' m' ->
      cl_step ge (State ve te (Kseq (Swhile a s) :: k)) m st' m'

  | step_dowhile: forall ve te k m a s st' m',
      cl_step ge (State ve te (Kseq s :: Kseq Scontinue :: Kfor2 a Sskip s :: k)) m st' m' ->
      cl_step ge (State ve te (Kseq (Sdowhile a s) :: k)) m st' m'

  | step_for: forall ve te k m a2 a3 s v2 b,
      Clight_sem.eval_expr ge ve te m a2 v2 ->
      bool_val v2 (typeof a2) = Some b ->
      cl_step ge (State ve te (Kseq (Sfor' a2 a3 s) :: k)) m (State ve te (if b then Kseq s :: Kseq Scontinue :: Kfor2 a2 a3 s :: k else k)) m

  | step_for3: forall ve te k m a2 a3 s v2 b,
      Clight_sem.eval_expr ge ve te m a2 v2 ->
      bool_val v2 (typeof a2) = Some b ->
      cl_step ge (State ve te (Kfor3 a2 a3 s :: k)) m (State ve te (if b then Kseq s :: Kseq Scontinue :: Kfor2 a2 a3 s :: k else k)) m

  | step_return: forall f ve te optexp optid k m v' m' ve' te' te'' k',
      call_cont k = Kcall optid f ve' te' :: k' ->
      Mem.free_list m (Csem.blocks_of_env ve) = Some m' ->
      match optexp with None => True
                                  | Some a => exists v, Clight_sem.eval_expr ge ve te m a v /\ sem_cast v (typeof a) f.(fn_return) = Some v' 
                            end ->
      match optid with None => f.(fn_return) = Tvoid /\ te''=te'
                                | Some id => optexp <> None /\ te'' = PTree.set id v' te'
      end ->
      cl_step ge (State ve te (Kseq (Sreturn optexp) :: k)) m (State ve' te'' k') m'

  | step_switch: forall ve te k m a sl n,
      Clight_sem.eval_expr ge ve te m a (Vint n) ->
      cl_step ge (State ve te (Kseq (Sswitch a sl) :: k)) m
              (State ve te (Kseq (seq_of_labeled_statement (select_switch n sl)) :: Kswitch :: k)) m

  | step_label: forall ve te k m lbl s st' m',
       cl_step ge (State ve te (Kseq s :: k)) m st' m' ->
       cl_step ge (State ve te (Kseq (Slabel lbl s) :: k)) m st' m'

  | step_goto: forall f ve te k m lbl k'
                     (* make sure to take a step here, so that every loop ticks the clock *) 
      (CUR: current_function k = Some f),
      find_label lbl f.(fn_body) (Kseq (Sreturn None) :: (call_cont k)) = Some k' ->
      cl_step ge (State ve te (Kseq (Sgoto lbl) :: k)) m (State ve te k') m.

Definition vret2v (vret: list val) : val :=
  match vret with v::nil => v | _ => Vundef end.

Definition exit_syscall_number : ident := 1%positive.

(*LENB: TYPE HAS CHANGED FROM  genv -> corestate -> mem -> option val
   to G -> C -> option int 
Definition cl_safely_halted (ge: genv) (c: corestate) (m: mem) : option val := None.
*)
Definition cl_safely_halted (ge: genv) (c: corestate): option int := None.

Definition empty_function : function := mkfunction Tvoid nil nil nil Sskip.

Fixpoint temp_bindings (i: positive) (vl: list val) :=
 match vl with
 | nil => PTree.empty val
 | v::vl' => PTree.set i v (temp_bindings (i+1)%positive vl')
 end.

Definition Tint32s := Tint I32 Signed noattr.
Definition true_expr : Clight.expr := Clight.Econst_int Int.one Tint32s.

Fixpoint typed_params (i: positive) (n: nat) : list (ident * type) :=
 match n with
 | O => nil
 | S n' => (i, Tint32s) :: typed_params (i+1)%positive n'
 end.

Definition cl_initial_core (ge: genv) (v: val) (args: list val) : option corestate := 
  let tl := typed_params 2%positive (length args)
   in Some (State empty_env (temp_bindings 1%positive (v::args))
                  (Kseq (Scall None 
                                  (Etempvar 1%positive (Tfunction (type_of_params tl) Tvoid))
                                  (map (fun x => Etempvar (fst x) (snd x)) tl)) :: 
                     Kseq (Swhile true_expr Sskip) :: nil)).

Lemma cl_corestep_not_at_external:
  forall ge m q m' q', cl_step ge q m q' m' -> cl_at_external q = None.
Proof.
  intros.
  destruct q; simpl; auto. inv H.
Qed.

(*LENB: TYPES HAVE CHANGED
Lemma cl_corestep_not_halted :
  forall ge m q m' q', cl_step ge q m q' m' -> cl_safely_halted ge q m = None.
Proof.
  intros.
  simpl; auto.
Qed.*)
Lemma cl_corestep_not_halted :
  forall ge m q m' q', cl_step ge q m q' m' -> cl_safely_halted ge q = None.
Proof.
  intros.
  simpl; auto.
Qed.

Lemma cl_at_external_halted_excl :
       forall ge q,cl_at_external q = None \/ cl_safely_halted ge q = None.
 Proof. intros.  right. trivial. Qed.


(*LENB: TYPE OF CoreSemantics HAS CHANGED
Program Definition cl_core_sem : CoreSemantics (Genv.t fundef type) corestate mem external_function :=
  @Build_CoreSemantics _ _ _ _
    cl_initial_core
    cl_at_external
    cl_after_external
    cl_safely_halted
    cl_step
    cl_corestep_not_at_external 
    cl_corestep_not_halted _.
*)

Definition cl_init_mem (ge:genv)  (m:mem) d:  Prop:=
   Genv.alloc_variables ge Mem.empty d = Some m.
(*Defined initial memory, by adapting the definition of Genv.init_mem*)

Definition cl_core_sem : CoreSemantics genv corestate mem  (list (ident * globvar type)) :=
  @Build_CoreSemantics _ _ _ _ 
    cl_init_mem
    cl_initial_core
    cl_at_external
    cl_after_external
    cl_safely_halted
    cl_step
    cl_corestep_not_at_external 
    cl_corestep_not_halted
    cl_at_external_halted_excl .

(*
Program Definition cl_core_sem : CoreSemantics (Genv.t fundef type) corestate mem.
  eapply @Build_CoreSemantics with (corestep:=cl_step).
       apply cl_init_mem.
       apply  cl_initial_core.
       apply cl_after_external.
       apply cl_corestep_not_at_external.  
       apply cl_corestep_not_halted.
       intros. right; trivial.  Defined.
*)

Lemma cl_corestep_fun: forall ge m q m1 q1 m2 q2, 
    cl_step ge q m q1 m1 -> 
    cl_step ge q m q2 m2 -> 
    (q1,m1)=(q2,m2).
Proof.
intros.
rename H0 into STEP;
revert q2 m2 STEP; induction H; intros; inv STEP; simpl; auto; repeat fun_tac; auto.
inversion2 H H13. repeat fun_tac; auto.
inversion2 H H7.
destruct optexp. destruct H1 as [v [? ?]]. destruct H12 as [v2 [? ?]].
repeat fun_tac.
destruct optid. subst. auto. destruct H13,H2; subst; auto.
destruct H2,H13; subst; auto.
destruct optid; subst; auto. destruct H2; congruence.
destruct H2,H13; subst; auto.
inv H; auto.
Qed.

Lemma free_list_allowed_core_mod : forall m1 l m2,
  Mem.free_list m1 l = Some m2 ->
  allowed_core_modification m1 m2.
Proof.
  intros m1 l m2; revert m1; induction l; simpl; intros.
  inv H;   eauto with allowed_mod.
  destruct a; destruct p; invSome; eauto with allowed_mod.
Qed.

Hint Resolve free_list_allowed_core_mod : allowed_mod.

Lemma cl_allowed_modifications : forall ge c m c' m',
  cl_step ge c m c' m' -> allowed_core_modification m m'.
Proof.
  intros.
  induction H; eauto with allowed_mod.
  inv H3; eauto with allowed_mod. congruence.
  admit.  (* need allowed_mod theorems about loadbytes and storebytes *)
  apply allowed_core_modification_trans with m1.
  clear - H5.
  forget (fn_params f ++ fn_vars f) as l.
  induction H5; eauto with allowed_mod.
  forget (fn_params f) as l.
  clear - H6; induction H6; eauto with allowed_mod.
Qed.

(*LENB: TYPE HAS CHANGED
Definition cl_core_sem' : CompcertCoreSem (Genv.t fundef type) corestate external_function :=
  Build_CompcertCoreSem _ _ _ cl_core_sem cl_corestep_fun cl_allowed_modifications.
*)
Definition cl_core_sem' : CompcertCoreSem (Genv.t fundef type) corestate (list (ident * globvar type)) :=
  Build_CompcertCoreSem _ _ _ cl_core_sem  cl_corestep_fun cl_allowed_modifications.

