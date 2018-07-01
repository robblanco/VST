(* Clight SEmantics for Machines*)

(*
  We define event semantics for 
  - Clight_new: the core semantics defined by VST
  - Clightcore: the core semantics derived from 
    CompCert's Clight
*)

Require Import compcert.common.Memory.
Require Import VST.veric.compcert_rmaps.
Require Import VST.veric.juicy_mem.
Require Import VST.veric.res_predicates.

(*IM using proof irrelevance!*)
Require Import ProofIrrelevance.

(* The concurrent machinery*)
Require Import VST.concurrency.common.core_semantics.
Require Import VST.concurrency.common.scheduler.
Require Import VST.concurrency.common.HybridMachineSig.
Require Import VST.concurrency.common.semantics.
Require Import VST.concurrency.common.lksize.
Require Import VST.concurrency.common.permissions.

(*Semantics*)
Require Import VST.veric.Clight_new.
Require Import VST.veric.Clightnew_coop.
Require Import VST.veric.Clight_core.
Require Import VST.veric.Clightcore_coop. 
Require Import VST.sepcomp.event_semantics.
Require Import VST.veric.Clight_sim.

Inductive deref_locT (ty : type) (m : mem) (b : block) (ofs : ptrofs) : val -> list mem_event -> Prop :=
    deref_locT_value : forall (chunk : memory_chunk) bytes,
                      access_mode ty = By_value chunk ->
                      (align_chunk chunk | (Ptrofs.unsigned ofs)) ->
                      Mem.loadbytes m b (Ptrofs.unsigned ofs) (size_chunk chunk) = Some bytes ->
(*                      Mem.load chunk m b (Ptrofs.unsigned ofs) = Some (decode_val chunk bytes) ->*)
                      deref_locT ty m b ofs (decode_val chunk bytes) (Read b (Ptrofs.unsigned ofs) (size_chunk chunk) bytes :: nil)
  | deref_locT_reference : access_mode ty = By_reference -> deref_locT ty m b ofs (Vptr b ofs) nil
  | deref_locT_copy : access_mode ty = By_copy -> deref_locT ty m b ofs (Vptr b ofs) nil.

Lemma deref_locT_ax1 a m loc ofs v T (D:deref_locT (typeof a) m loc ofs v T):
      deref_loc (typeof a) m loc ofs v.
Proof. 
  inv D.
  + eapply deref_loc_value; eauto. eapply Mem.loadbytes_load; eauto.
  + apply deref_loc_reference; trivial.
  + apply deref_loc_copy; trivial.
Qed.

Lemma deref_locT_ax2 a m loc ofs v (D:deref_loc (typeof a) m loc ofs v):
      exists T, deref_locT (typeof a) m loc ofs v T.
Proof. 
  inv D.
  + exploit Mem.load_valid_access; eauto. intros [_ ALGN].
    exploit Mem.load_loadbytes; eauto. intros [bytes [LD V]]; subst v.
    eexists; eapply deref_locT_value; eauto. 
  + eexists; apply deref_locT_reference; trivial.
  + eexists; apply deref_locT_copy; trivial.
Qed.

Lemma deref_locT_fun a m loc ofs v1 T1 (D1:deref_locT (typeof a) m loc ofs v1 T1)
      v2 T2 (D2:deref_locT (typeof a) m loc ofs v2 T2): (v1,T1)=(v2,T2). 
Proof. inv D1; inv D2; try congruence. Qed.
(*
Lemma deref_locT_elim: forall a m b ofs v T (D:deref_locT (typeof a) m loc ofs v T),
       ev_elim m T m' /\
       (forall mm mm', ev_elim mm T mm' -> exists cc', ev_step c mm T cc' mm')
 *)

Inductive alloc_variablesT (g: genv): PTree.t (block * type) -> mem -> list (ident * type) ->
                                      PTree.t (block * type) -> mem -> (list mem_event) -> Prop :=
    alloc_variablesT_nil : forall e m, alloc_variablesT g e m nil e m nil
  | alloc_variablesT_cons :
      forall e m id ty vars m1 b1 m2 e2 T,
        Mem.alloc m 0 (@sizeof g ty) = (m1, b1) ->
        alloc_variablesT g (PTree.set id (b1, ty) e) m1 vars e2 m2 T ->
        alloc_variablesT g e m ((id, ty) :: vars) e2 m2 (Alloc b1 0 (@sizeof g ty) :: T).

Lemma alloc_variablesT_ax1 g: forall e m l e' m' T (A:alloc_variablesT g e m l e' m' T),
    alloc_variables g e m l e' m'.
Proof. intros. induction A. constructor. econstructor; eauto. Qed. 

Lemma alloc_variablesT_ax2 g: forall e m l e' m' (A:alloc_variables g e m l e' m'),
    exists T, alloc_variablesT g e m l e' m' T.
Proof. intros. induction A. exists nil. constructor.
       destruct IHA. eexists. econstructor; eauto.
Qed. 
    
Lemma alloc_variablesT_fun g: forall e m l e' m' T' (A:alloc_variablesT g e m l e' m' T')
                                     e2 m2 T2 (A2:alloc_variablesT g e m l e2 m2 T2),
     (e',m',T') = (e2,m2,T2).
Proof. intros until T'. intros A; induction A; intros.
       + inv A2. trivial.
       + inv A2. rewrite H8 in H; inv H. apply IHA in H9; inv H9. trivial.
Qed. 
   
Section EXPR_T.
(** Extends Clight.eval_expr etc with event traces. *)

Variable g: genv.
Variable e: env.
Variable le: temp_env.
Variable m: mem.

Inductive eval_exprT: expr -> val -> list mem_event-> Prop :=
  | evalT_Econst_int:   forall i ty,
      eval_exprT (Econst_int i ty) (Vint i) nil
  | evalT_Econst_float:   forall f ty,
      eval_exprT (Econst_float f ty) (Vfloat f) nil
  | evalT_Econst_single:   forall f ty,
      eval_exprT (Econst_single f ty) (Vsingle f) nil
  | evalT_Econst_long:   forall i ty,
      eval_exprT (Econst_long i ty) (Vlong i) nil
  | evalT_Etempvar:  forall id ty v,
      le!id = Some v ->
      eval_exprT (Etempvar id ty) v nil
  | evalT_Eaddrof: forall a ty loc ofs T,
      eval_lvalueT a loc ofs T ->
      eval_exprT (Eaddrof a ty) (Vptr loc ofs) T
  | evalT_Eunop:  forall op a ty v1 v T,
      eval_exprT a v1 T ->
      sem_unary_operation op v1 (typeof a) m = Some v ->
      (*unops at most check weak_valid_ptr, so don't create a trace event*)
      eval_exprT (Eunop op a ty) v T
  | evalT_Ebinop: forall op a1 a2 ty v1 v2 v T1 T2,
      eval_exprT a1 v1 T1 ->
      eval_exprT a2 v2 T2 ->
      sem_binary_operation g op v1 (typeof a1) v2 (typeof a2) m = Some v ->
      (*binops at most check weak_valid_ptr or cast, so don't create a trace event*)
      eval_exprT (Ebinop op a1 a2 ty) v (T1++T2)
  | evalT_Ecast:   forall a ty v1 v T,
      eval_exprT a v1 T ->
      sem_cast v1 (typeof a) ty m = Some v ->
      eval_exprT (Ecast a ty) v T
  | evalT_Esizeof: forall ty1 ty,
      eval_exprT (Esizeof ty1 ty) (Vptrofs (Ptrofs.repr (@sizeof g ty1))) nil
  | evalT_Ealignof: forall ty1 ty,
      eval_exprT (Ealignof ty1 ty) (Vptrofs (Ptrofs.repr (@alignof g ty1))) nil
  | evalT_Elvalue: forall a loc ofs v T1 T2 T,
      eval_lvalueT a loc ofs T1 ->
      deref_locT (typeof a) m loc ofs v T2 -> T=(T1 ++ T2) ->
      eval_exprT a v T

with eval_lvalueT: expr -> block -> ptrofs -> list mem_event-> Prop :=
  | evalT_Evar_local:   forall id l ty,
      e!id = Some(l, ty) ->
      eval_lvalueT (Evar id ty) l Ptrofs.zero nil
  | evalT_Evar_global: forall id l ty,
      e!id = None ->
      Genv.find_symbol g id = Some l ->
      eval_lvalueT (Evar id ty) l Ptrofs.zero nil
  | evalT_Ederef: forall a ty l ofs T,
      eval_exprT a (Vptr l ofs) T ->
      eval_lvalueT (Ederef a ty) l ofs T
 | evalT_Efield_struct:   forall a i ty l ofs id co att delta T,
      eval_exprT a (Vptr l ofs) T ->
      typeof a = Tstruct id att ->
      g.(genv_cenv)!id = Some co ->
      field_offset g i (co_members co) = Errors.OK delta ->
      eval_lvalueT (Efield a i ty) l (Ptrofs.add ofs (Ptrofs.repr delta)) T
 | evalT_Efield_union:   forall a i ty l ofs id co att T,
      eval_exprT a (Vptr l ofs) T ->
      typeof a = Tunion id att ->
      g.(genv_cenv)!id = Some co ->
      eval_lvalueT (Efield a i ty) l ofs T.

Scheme eval_exprT_ind2 := Minimality for eval_exprT Sort Prop
  with eval_lvalueT_ind2 := Minimality for eval_lvalueT Sort Prop.
Combined Scheme eval_exprT_lvalue_ind from eval_exprT_ind2, eval_lvalueT_ind2.

Inductive eval_exprTlist: list expr -> typelist -> list val -> list mem_event-> Prop :=
  | eval_ETnil:
      eval_exprTlist nil Tnil nil nil
  | eval_ETcons:   forall a bl ty tyl v1 v2 vl T1 T2,
      eval_exprT a v1 T1 ->
      sem_cast v1 (typeof a) ty m = Some v2 ->
      eval_exprTlist bl tyl vl T2 ->
      eval_exprTlist (a :: bl) (Tcons ty tyl) (v2 :: vl) (T1++T2).

Lemma eval_exprT_ax1: forall a v T, eval_exprT a v T -> eval_expr g e le m a v
with eval_lvalueT_ax1: forall a b z T, eval_lvalueT a b z T -> eval_lvalue g e le m a b z.           
Proof.
  + induction 1; econstructor; eauto. eapply deref_locT_ax1; eauto.
  + induction 1; try solve [econstructor; eauto].
Qed.

Lemma eval_exprT_ax2: forall a v, eval_expr g e le m a v -> exists T, eval_exprT a v T
with eval_lvalueT_ax2: forall a b z, eval_lvalue g e le m a b z -> exists T, eval_lvalueT a b z T.
Proof.
  + induction 1; try solve [eexists; econstructor; eauto].
  - apply eval_lvalueT_ax2 in H; destruct H. eexists; eapply evalT_Eaddrof; eauto.
  - destruct IHeval_expr. eexists; eapply evalT_Eunop; eauto.
  - destruct IHeval_expr1. destruct IHeval_expr2. eexists; eapply evalT_Ebinop; eauto.
  - destruct IHeval_expr. eexists; eapply evalT_Ecast; eauto.
  - apply eval_lvalueT_ax2 in H; destruct H.
    apply deref_locT_ax2 in H0. destruct H0. eexists; eapply evalT_Elvalue; eauto.
  + induction 1; try solve [eexists; econstructor; eauto].
  - apply eval_exprT_ax2 in H; destruct H as [T H]. eexists; eapply evalT_Ederef; eauto.
  - apply eval_exprT_ax2 in H; destruct H as [T H]. eexists; eapply evalT_Efield_struct; eauto.
  - apply eval_exprT_ax2 in H; destruct H as [T H]. eexists; eapply evalT_Efield_union; eauto.
Qed.

  Lemma eval_exprT_lvalueT_fun:
    (forall a v1 T1 v2 T2, eval_exprT a v1 T1 -> eval_exprT a v2 T2 -> (v1,T1)=(v2,T2)) /\
    (forall a b1 b2 i1 i2 T1 T2, eval_lvalueT a b1 i1 T1 -> eval_lvalueT a b2 i2 T2 ->
                               (b1,i1,T1)=(b2,i2,T2)).
Proof.
 destruct (eval_exprT_lvalue_ind
   (fun a v T =>  forall v' T', eval_exprT a v' T' -> (v,T)=(v',T'))
   (fun a b i T => forall b' i' T', eval_lvalueT a b' i' T' -> (b,i,T)=(b',i',T')));
   simpl; intros.
 
 { inv H. trivial. inv H0. }
 { inv H. trivial. inv H0. }
 { inv H. trivial. inv H0. }
 { inv H. trivial. inv H0. }
 { inv H. inv H0. congruence. inv H. }
 { inv H1. { apply H0 in H6; congruence. }
           { inv H2. } }
 { inv H2. { apply H0 in H8; congruence. } 
           { inv H3. } }
 { inv H4. { apply H0 in H11; inv H11. apply H2 in H12; congruence. }
           { inv H5. } }
 { inv H2. { apply H0 in H5; congruence. } 
           { inv H3.  } }
 { inv H. trivial. inv H0. }
 { inv H. trivial. inv H0. }
 { inv H. { inv H3. apply H0 in H; inv H. exploit deref_locT_fun. apply H1. apply H2. intros X; inv X; trivial. }
          { inv H3. apply H0 in H; inv H. exploit deref_locT_fun. apply H1. apply H2. intros X; inv X; trivial. }
          { inv H3. apply H0 in H; inv H. exploit deref_locT_fun. apply H1. apply H2. intros X; inv X; trivial. }
          { inv H3. apply H0 in H; inv H. exploit deref_locT_fun. apply H1. apply H2. intros X; inv X; trivial. }
          { inv H3. apply H0 in H; inv H. exploit deref_locT_fun. apply H1. apply H2. intros X; inv X; trivial. } }
 { inv H0; congruence. }
 { inv H1; congruence. }
 { inv H1. apply H0 in H7; congruence. }
 { inv H4. { apply H0 in H8; congruence. }
           { congruence. } }
 { inv H3. { congruence. }
           { apply H0 in H7; congruence. } }

 split; intros. apply (H _ _ _ H1 _ _ H2). apply (H0 _ _ _ _ H1 _ _ _ H2).
Qed.

Lemma eval_exprT_fun a v1 T1 v2 T2: eval_exprT a v1 T1 -> eval_exprT a v2 T2 -> (v1,T1)=(v2,T2).
Proof. apply eval_exprT_lvalueT_fun. Qed.

Lemma eval_lvalueT_fun a b1 b2 i1 i2 T1 T2: eval_lvalueT a b1 i1 T1 -> eval_lvalueT a b2 i2 T2 ->
                               (b1,i1,T1)=(b2,i2,T2).
Proof. apply eval_exprT_lvalueT_fun. Qed.

Lemma eval_exprTlist_ax1: forall es ts vs T (E:eval_exprTlist es ts vs T),
      eval_exprlist g e le m es ts vs.
Proof.
  intros; induction E; simpl; intros. econstructor.
  apply eval_exprT_ax1 in H. econstructor; eauto.
Qed.

Lemma eval_exprTlist_ax2: forall es ts vs (E:eval_exprlist g e le m es ts vs),
      exists T, eval_exprTlist es ts vs T.
Proof.
  intros; induction E; simpl; intros. eexists; econstructor.
  apply eval_exprT_ax2 in H. destruct H as [T1 H]. destruct IHE as [T2 K].
  eexists. econstructor; eauto.
Qed.

Lemma eval_exprTlist_fun: forall es ts vs1 T1 (E1:eval_exprTlist es ts vs1 T1)
                          vs2 T2 (E2:eval_exprTlist es ts vs2 T2), (vs1,T1)=(vs2,T2).
Proof.
  intros es ts vs1 T1 E; induction E; simpl; intros; inv E2; trivial.
  exploit eval_exprT_fun. apply H. apply H5. intros X; inv X. rewrite H8 in H0; inv H0.
  apply IHE in H9; congruence. 
Qed.

End EXPR_T.

Inductive assign_locT (ce : composite_env) (ty : type) (m : mem) (b : block) (ofs : ptrofs)
  : val -> mem -> list mem_event -> Prop :=
    assign_locT_value : forall (v : val) (chunk : memory_chunk) (m' : mem),
                       access_mode ty = By_value chunk ->
                       Mem.storev chunk m (Vptr b ofs) v = Some m' ->
                       assign_locT ce ty m b ofs v m' (Write b (Ptrofs.unsigned ofs) (encode_val chunk v) ::nil)
  | assign_locT_copy : forall (b' : block) (ofs' : ptrofs) (bytes : list memval) (m' : mem),
                      access_mode ty = By_copy ->
                      (sizeof ty > 0 -> (alignof_blockcopy ce ty | Ptrofs.unsigned ofs')) ->
                      (sizeof ty > 0 -> (alignof_blockcopy ce ty | Ptrofs.unsigned ofs)) ->
                      b' <> b \/
                      Ptrofs.unsigned ofs' = Ptrofs.unsigned ofs \/
                      Ptrofs.unsigned ofs' + sizeof ty <= Ptrofs.unsigned ofs \/
                      Ptrofs.unsigned ofs + sizeof ty <= Ptrofs.unsigned ofs' ->
                      Mem.loadbytes m b' (Ptrofs.unsigned ofs') (sizeof ty) = Some bytes ->
                      Mem.storebytes m b (Ptrofs.unsigned ofs) bytes = Some m' ->
                      assign_locT ce ty m b ofs (Vptr b' ofs') m'
                                  (Read b' (Ptrofs.unsigned ofs') (sizeof ty) bytes ::
                                   Write b (Ptrofs.unsigned ofs) bytes :: nil).

Lemma assign_locT_ax1 ce ty m b ofs v m' T (A:assign_locT ce ty m b ofs v m' T):
    assign_loc ce ty m b ofs v m'. 
Proof.
  destruct A; [eapply assign_loc_value; eauto | eapply assign_loc_copy; eauto].
Qed.

Lemma assign_locT_ax2 ce ty m b ofs v m' (A:assign_loc ce ty m b ofs v m'):
    exists T, assign_locT ce ty m b ofs v m' T. 
Proof.
  destruct A; eexists; [eapply assign_locT_value; eauto | eapply assign_locT_copy; eauto].
Qed.

Lemma assign_locT_fun ce ty m b ofs v m1 T1
      (A1:assign_locT ce ty m b ofs v m1 T1) m2 T2 (A2:assign_locT ce ty m b ofs v m2 T2):
      (m1,T1)=(m2,T2).
Proof. inv A1; inv A2; congruence. Qed.

Section ClightSEM.
  Definition F: Type := fundef.
  Definition V: Type := type.
  Definition G := genv.
  Definition C := corestate.
  Definition getEnv (g:G): Genv.t F V := genv_genv g.
  (* We might want to define this properly or
     factor the machines so we don't need events here. *)
  
(** Transition relation *)

Inductive cl_evstep (ge: Clight.genv): forall (q: corestate) (m: mem) (T:list mem_event) (q': corestate) (m': mem), Prop :=

  | evstep_assign: forall ve te k m a1 a2 loc ofs v2 v m' T1 T2 T3,
     type_is_volatile (typeof a1) = false ->
      eval_lvalueT ge ve te m a1 loc ofs T1 ->
      eval_exprT ge ve te m a2 v2 T2 ->
      Cop.sem_cast v2 (typeof a2) (typeof a1) m = Some v ->
      assign_locT ge (typeof a1) m loc ofs v m' T3 ->
      cl_evstep ge (State ve te (Kseq (Sassign a1 a2):: k)) m (T1++T2++T3) (State ve te k) m'

  | evstep_set:   forall ve te k m id a v T,
      eval_exprT ge ve te m a v T ->
      cl_evstep ge (State ve te (Kseq (Sset id a) :: k)) m T (State ve (PTree.set id v te) k) m

  | evstep_call_internal:   forall ve te k m optid a al tyargs tyres cc vf vargs f m1 ve' le' T1 T2 T3,
      Cop.classify_fun (typeof a) = Cop.fun_case_f tyargs tyres cc ->
      eval_exprT ge ve te m a vf T1 ->
      eval_exprTlist ge ve te m al tyargs vargs T2 ->
      Genv.find_funct ge vf = Some (Internal f) ->
      type_of_function f = Tfunction tyargs tyres cc ->
      list_norepet (var_names f.(fn_params) ++ var_names f.(fn_temps)) ->
      forall (NRV: list_norepet (var_names f.(fn_vars))),
      alloc_variablesT ge empty_env m (f.(fn_vars)) ve' m1 T3 ->
      bind_parameter_temps f.(fn_params) vargs (create_undef_temps f.(fn_temps)) = Some
le' ->
      cl_evstep ge (State ve te (Kseq (Scall optid a al) :: k)) m (T1++T2++T3)
                   (State ve' le' (Kseq f.(fn_body) :: Kseq (Sreturn None) :: Kcall optid f ve te :: k)) m1.
(*
  | evstep_call_external:   forall ve te k m optid a al tyargs tyres cc vf vargs ef,
      Cop.classify_fun (typeof a) = Cop.fun_case_f tyargs tyres cc ->
      Clight.eval_expr ge ve te m a vf ->
      Clight.eval_exprlist ge ve te m al tyargs vargs ->
      Genv.find_funct ge vf = Some (External ef tyargs tyres cc) ->
      cl_evstep ge (State ve te (Kseq (Scall optid a al) :: k)) m (ExtCall ef vargs optid ve te k) m

  | evstep_seq: forall ve te k m s1 s2 st' m',
          cl_evstep ge (State ve te (Kseq s1 :: Kseq s2 :: k)) m st' m' ->
          cl_evstep ge (State ve te (Kseq (Ssequence s1 s2) :: k)) m st' m'

  | evstep_skip: forall ve te k m st' m',
          cl_evstep ge (State ve te k) m st' m' ->
          cl_evstep ge (State ve te (Kseq Sskip :: k)) m st' m'

  | evstep_continue: forall ve te k m st' m',
           cl_evstep ge (State ve te (continue_cont k)) m st' m' ->
           cl_evstep ge (State ve te (Kseq Scontinue :: k)) m st' m'

  | evstep_break: forall ve te k m st' m',
                   cl_evstep ge (State ve te (break_cont k)) m st' m' ->
                   cl_evstep ge (State ve te (Kseq Sbreak :: k)) m st' m'

  | evstep_ifthenelse:  forall ve te k m a s1 s2 v1 b,
      Clight.eval_expr ge ve te m a v1 ->
      Cop.bool_val v1 (typeof a) m = Some b ->
      cl_evstep ge (State ve te (Kseq (Sifthenelse a s1 s2) :: k)) m (State ve te  (Kseq (if b then s1 else s2) :: k)) m

  | evstep_for: forall ve te k m s1 s2,
      cl_evstep ge (State ve te (Kseq (Sloop s1 s2) :: k)) m
              (State ve te (Kseq s1 :: Kseq Scontinue :: Kloop1 s1 s2 :: k)) m

  | evstep_loop2: forall ve te k m a3 s,
      cl_evstep ge (State ve te (Kloop2 s a3 :: k)) m
             (State ve te (Kseq s :: Kseq Scontinue :: Kloop1 s a3 :: k)) m

  | evstep_return: forall f ve te optexp optid k m v' m' ve' te' te'' k',
      call_cont k = Kcall optid f ve' te' :: k' ->
      Mem.free_list m (Clight.blocks_of_env ge ve) = Some m' ->
      match optexp with None => v' = Vundef
                                  | Some a => exists v, Clight.eval_expr ge ve te m a v
                                     /\ Cop.sem_cast v (typeof a) f.(fn_return) m = Some v'
                            end ->
      match optid with None => True /\ te''=te'
                                | Some id => True /\ te'' = PTree.set id v' te'
      end ->
      cl_evstep ge (State ve te (Kseq (Sreturn optexp) :: k)) m (State ve' te'' k') m'

  | evstep_switch: forall ve te k m a sl v n,
      Clight.eval_expr ge ve te m a v ->
      Cop.sem_switch_arg v (typeof a) = Some n ->
      cl_evstep ge (State ve te (Kseq (Sswitch a sl) :: k)) m
              (State ve te (Kseq (seq_of_labeled_statement (select_switch n sl)) :: Kswitch :: k)) m

  | evstep_label: forall ve te k m lbl s st' m',
       cl_evstep ge (State ve te (Kseq s :: k)) m st' m' ->
       cl_evstep ge (State ve te (Kseq (Slabel lbl s) :: k)) m st' m'

  | evstep_goto: forall f ve te k m lbl k'
                     (* make sure to take a step here, so that every loop ticks the clock *)
      (CUR: current_function k = Some f),
      find_label lbl f.(fn_body) (Kseq (Sreturn None) :: (call_cont k)) = Some k' ->
      cl_evstep ge (State ve te (Kseq (Sgoto lbl) :: k)) m (State ve te k') m.
 *)

  Lemma CLN_evstep_ax1 ge : forall c m T c' m' (H: cl_evstep ge c m T c' m' ),
    corestep (CLN_memsem ge) c m c' m'.
  Proof.
    induction 1.
    + apply eval_lvalueT_ax1 in H0. apply eval_exprT_ax1 in H1.
      apply assign_locT_ax1 in H3. econstructor; eauto.
    + apply eval_exprT_ax1 in H. econstructor; eauto.
    + apply eval_exprT_ax1 in H0.
      apply eval_exprTlist_ax1 in H1.
      apply alloc_variablesT_ax1 in H5. econstructor; eauto.
  Qed.   
  
  Lemma CLN_evstep_ax2 ge : forall c m c' m' (H:corestep (CLN_memsem ge) c m c' m'),
      exists T : list mem_event, cl_evstep ge c m T c' m'.
  Proof.
    induction 1.
    { apply eval_lvalueT_ax2 in H0. destruct H0 as [T1 A1].
      apply eval_exprT_ax2 in H1. destruct H1 as [T2 A2].
      apply assign_locT_ax2 in H3. destruct H3 as [T3 A3].
      eexists; econstructor; eauto. }
    { apply eval_exprT_ax2 in H. destruct H as [T H]. eexists; econstructor; eauto. }
    { apply eval_exprT_ax2 in H0. destruct H0 as [T1 K1].
      apply eval_exprTlist_ax2 in H1. destruct H1 as [T2 K2].
      apply alloc_variablesT_ax2 in H5. destruct H5 as [T3 K3]. eexists; econstructor; eauto.
  Admitted.

  Lemma CLN_evstep_fun ge : forall c m T' c' m' T'' c'' m''
                                   (K: cl_evstep ge c m T' c' m') (K': cl_evstep ge c m T'' c'' m''), T' = T''.
  Proof. intros. generalize dependent m''. generalize dependent c''. generalize dependent T''.
         induction K; simpl; intros; inv K'.
  + exploit eval_exprT_fun. apply H15. apply H1. intros X; inv X.
    exploit eval_lvalueT_fun. apply H14. apply H0. intros X; inv X.
    rewrite H16 in H2; inv H2.
    exploit assign_locT_fun. apply H17. apply H3. intros X; inv X; trivial.
  + exploit eval_exprT_fun. apply H9. apply H. intros X; inv X. trivial.
  + rewrite H13 in H; inv H.
    exploit eval_exprT_fun. apply H14. apply H0. intros X; inv X.
    exploit eval_exprTlist_fun. apply H15. apply H1. intros X; inv X.
    rewrite H20 in H2; inv H2.
    rewrite H24 in H6; inv H6.
    exploit alloc_variablesT_fun. apply H23. apply H5. intros X; inv X; trivial.
  Qed.
  
  (*
  Lemma CLN_evstep_elim ge : forall c m T c' m' (K: cl_evstep ge c m T c' m'),
        ev_elim m T m' /\
        (forall mm mm', ev_elim mm T mm' -> exists cc', cl_evstep ge c mm T cc' mm').
  Proof.
    induction 1.
    + inv H3.
    - simpl in *; split. apply Mem.store_storebytes in H5.
      exists m'; split; trivial.
      intros mm mm' [m2 [M ?]]; subst m2.
      eexists. eapply evstep_assign; eauto.
      Search Mem.storebytes Mem.store.
    (** *Event semantics for Clight_new*)
   (* This should be a version of CLN_memsem annotated with memory events. *)*)
  
  Program Definition CLN_evsem ge : @EvSem C := {| msem := CLN_memsem ge; ev_step := cl_evstep ge |}.
  Next Obligation. apply CLN_evstep_ax1. Qed.
  Next Obligation. apply CLN_evstep_ax2. Qed.
  Next Obligation. apply CLN_evstep_fun. Qed.
  Next Obligation.
  Admitted.
  

  Lemma CLN_msem : forall ge, msem (CLN_evsem ge) = CLN_memsem ge.
  Proof. auto. Qed.

  Lemma CLN_step_decay: forall g c m tr c' m',
      event_semantics.ev_step (CLN_evsem g) c m tr c' m' ->
      decay m m'.
 simpl.  Admitted.

  Lemma at_external_SEM_eq:
     forall ge c m, at_external (CLN_evsem ge) c m =
      match c with
      | State _ _ _ => None
      | ExtCall ef args _ _ _ _ => Some (ef, args)
      end.
  Proof. auto. Qed.

  Instance Clight_newSem ge : Semantics :=
    { semG := G; semC := C; semSem := CLN_evsem ge; the_ge := ge }.

  


  (** *Event semantics for Clight_core*)
  (* This should be a version of CLC_memsem annotated with memory events. *)
  Program Definition CLC_evsem ge : @EvSem state := {| msem := CLC_memsem ge |}.
  Next Obligation.
  Admitted.
  Next Obligation.
  Admitted.
  Next Obligation.
  Admitted.
  Next Obligation.
  Admitted.
  Next Obligation.
  Admitted.

  Lemma CLC_msem : forall ge, msem (CLC_evsem ge) = CLC_memsem ge.
  Proof. auto. Qed.


  Instance ClightSem ge : Semantics :=
    { semG := G; semC := state; semSem := CLC_evsem ge; the_ge := ge }.

  (* extending Clight_sim to event semantics *)
Inductive ev_star ge: state -> mem -> _ -> state -> mem -> Prop :=
  | ev_star_refl: forall s m,
      ev_star ge s m nil s m
  | ev_star_step: forall s1 m1 ev1 s2 m2 ev2 s3 m3,
      ev_step (CLC_evsem ge) s1 m1 ev1 s2 m2 -> ev_star ge s2 m2 ev2 s3 m3 ->
      ev_star ge s1 m1 (ev1 ++ ev2) s3 m3.

Lemma ev_star_one:
  forall ge s1 m1 ev s2 m2, ev_step (CLC_evsem ge) s1 m1 ev s2 m2 -> ev_star ge s1 m1 ev s2 m2.
Proof.
  intros. rewrite <- (app_nil_r ev). eapply ev_star_step; eauto. apply ev_star_refl.
Qed.

Lemma ev_star_two:
  forall ge s1 m1 ev1 s2 m2 ev2 s3 m3,
  ev_step (CLC_evsem ge) s1 m1 ev1 s2 m2 -> ev_step (CLC_evsem ge) s2 m2 ev2 s3 m3 ->
  ev_star ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  intros. eapply ev_star_step; eauto. apply ev_star_one; auto.
Qed.

Lemma ev_star_trans:
  forall ge {s1 m1 ev1 s2 m2}, ev_star ge s1 m1 ev1 s2 m2 ->
  forall {ev2 s3 m3}, ev_star ge s2 m2 ev2 s3 m3 -> ev_star ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  induction 1; intros; auto.
  rewrite <- app_assoc.
  eapply ev_star_step; eauto.
Qed.


Inductive ev_plus ge: state -> mem -> _ -> state -> mem -> Prop :=
  | ev_plus_left: forall s1 m1 ev1 s2 m2 ev2 s3 m3,
      ev_step (CLC_evsem ge) s1 m1 ev1 s2 m2 -> ev_star ge s2 m2 ev2 s3 m3 ->
      ev_plus ge s1 m1 (ev1 ++ ev2) s3 m3.

Lemma ev_plus_one:
  forall ge s1 m1 ev s2 m2, ev_step (CLC_evsem ge) s1 m1 ev s2 m2 -> ev_plus ge s1 m1 ev s2 m2.
Proof.
  intros. rewrite <- (app_nil_r ev). eapply ev_plus_left; eauto. apply ev_star_refl.
Qed.

Lemma ev_plus_two:
  forall ge s1 m1 ev1 s2 m2 ev2 s3 m3,
  ev_step (CLC_evsem ge) s1 m1 ev1 s2 m2 -> ev_step (CLC_evsem ge) s2 m2 ev2 s3 m3 ->
  ev_plus ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  intros. eapply ev_plus_left; eauto. apply ev_star_one; auto.
Qed.

Lemma ev_plus_star: forall ge s1 m1 ev s2 m2, ev_plus ge s1 m1 ev s2 m2 -> ev_star ge s1 m1 ev s2 m2.
Proof.
  intros. inv H. eapply ev_star_step; eauto.
Qed.

Lemma ev_plus_trans:
  forall ge {s1 m1 ev1 s2 m2}, ev_plus ge s1 m1 ev1 s2 m2 ->
  forall {ev2 s3 m3}, ev_plus ge s2 m2 ev2 s3 m3 -> ev_plus ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  intros.
  inv H.
  rewrite <- app_assoc.
  eapply ev_plus_left. eauto.
  eapply ev_star_trans; eauto.
  apply ev_plus_star. auto.
Qed.

Lemma ev_star_plus_trans:
  forall ge {s1 m1 ev1 s2 m2}, ev_star ge s1 m1 ev1 s2 m2 ->
  forall {ev2 s3 m3}, ev_plus ge s2 m2 ev2 s3 m3 -> ev_plus ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  intros. inv H. auto.
  rewrite <- app_assoc.
  eapply ev_plus_left; eauto.
  eapply ev_star_trans; eauto. apply ev_plus_star; auto.
Qed.

Lemma ev_plus_star_trans:
  forall ge {s1 m1 ev1 s2 m2}, ev_plus ge s1 m1 ev1 s2 m2 ->
  forall {ev2 s3 m3}, ev_star ge s2 m2 ev2 s3 m3 -> ev_plus ge s1 m1 (ev1 ++ ev2) s3 m3.
Proof.
  intros.
  inv H.
  rewrite <- app_assoc.
  eapply ev_plus_left; eauto. eapply ev_star_trans; eauto.
Qed.

  Lemma Clight_new_ev_sim : forall ge c1 m ev c1' m',
    event_semantics.ev_step (@semSem (Clight_newSem ge)) c1 m ev c1' m' ->
    forall c2, match_states c1 (fst (CC'.CC_state_to_CC_core c2)) ->
    exists c2', ev_plus ge c2 m ev c2' m' /\
      match_states c1' (fst (CC'.CC_state_to_CC_core c2')).
  Proof.
    (* based on Clight_sim.Clightnew_Clight_sim_eq_noOrder_SSplusConclusion *)
  Admitted.


End ClightSEM.