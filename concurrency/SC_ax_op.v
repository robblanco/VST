(** * Relating axiomatic SC semantics to the Erased machine (operational SC) *)

Require Import concurrency.Machine_ax.
Require Import concurrency.Executions_ax.
Require Import Coq.Sets.Ensembles.
Require Import Coq.Relations.Relations.
Require Import concurrency.Ensembles_util.
Require Import concurrency.Relations_util.

(** This proof is done in two steps:
    1. Valid SC executions ([validSC]) generated by the axiomatic semantics
       [step_po] are related to valid SC executions generated by an intermediate
       axiomatic semantics that follow the [sc] order instead.
    2. The intermediate axiomatic semantics are related to the operational
       SC semantics. *)

(** * Part 1 *)
Module AxiomaticIntermediate.

  Import Execution.
  Import ValidSC.
  Import AxSem.
  Import Order Enumerate.

  Section AxiomaticIntermediate.
    Context
      {lbl : Labels}
      {sem : Semantics}
      {threadpool : ThreadPool C}
      {genv : G}
      {exec : Execution}
      {po sc : relation id}.

    Variable cstep: G -> C ->  C -> list E -> Prop.

    Notation " '[' tp1 , Ex1 ']'   '==>{' n  '}'  '[' tp2 , Ex2 ']' " :=
      (stepN (Rstep cstep genv po sc) n tp1 Ex1 tp2 Ex2) (at level 40).

    Notation " '[' tp1 , Ex1 ']'  '==>po' '[' tp2 , Ex2 ']' " :=
      (step_po cstep genv po tp1 Ex1 tp2 Ex2) (at level 40).

    Notation " '[' tp1 , Ex1 ']'  '==>sc' '[' tp2 , Ex2 ']' " :=
      (Rstep cstep genv po sc tp1 Ex1 tp2 Ex2) (at level 40).

    Notation "tp1 '[' i , ls ']==>' tp2" :=
      (AxSem.step cstep genv tp1 i ls tp2) (at level 40).
    
    Record sim (n:nat) (Ex : events) (tp1 : t) (Ex1 : events) (tp2 : t) (Ex2 : events) :=
      { set_dis  : Disjoint _ Ex1 Ex2;
        set_inv  : Ex <--> Union _ Ex1 Ex2;
        sc_steps : [tp2, Ex2] ==>{n} [tp1, Empty_set _];
        ex_po    : forall e2, e2 \in Ex2 ->
                               forall e1, e1 \in Ex1 ->
                                            ~ po e1 e2;
        sc_tot   : strict_total_order sc Ex;
        po_sc    : inclusion _ po sc
      }.


    Lemma enumerate_hd:
      forall {A:Type} es R e es' e'
        (Htrans: transitive A R)
        (Henum: enumerate R es (e :: es'))
        (Hin: List.In e' es'),
        R e e'.
    Proof.
      intros.
      apply List.in_split in Hin.
      destruct Hin as [l1 [l2 Heq]].
      subst.
      eapply @enumerate_spec' with (es' := nil) (es'' := (l1 ++ e' :: l2)%list) in Henum;
        eauto.
      apply List.in_or_app; simpl;
        now auto.
    Qed.

    Import PeanoNat.Nat.

    (** ** Basic Properties of valid executions *)
    (** Not in [po] implies different threads *)
    Lemma no_po_thread_neq:
      forall e e'
        (Hneq: e <> e')
        (HpoWF: po_well_formed po)
        (Hpo1: ~ po e e')
        (Hpo2: ~ po e' e),
        thread e <> thread e'.
    Proof.
      intros.
      destruct (eq_dec (thread e) (thread e')) as [Htid_eq | Htid_neq];
        [destruct (po_same_thread _ HpoWF _ _ Htid_eq);
         now auto | assumption].
    Qed.

    (** Not in po implies that events are not related by Spawn *)
    Lemma no_po_spawn_neq:
      forall e e' es
        (Hneq: e <> e')
        (HpoWF: po_well_formed po)
        (Hpo1: ~ po e e')
        (Hpo2: ~ po e' e)
        (Henum: forall e'', List.In e'' es -> po e e''),
        ~ List.In (Spawn (thread e')) (List.map lab (e :: es)).
    Proof.
      intros.
      intros Hcontra.
      (** Since there was a [Spawn (thread e')] event in the trace (say e''),
              it is the case that (e'', e') \in po and (e, e'') \in po? *)
      assert (He'': lab e = Spawn (thread e') \/
                    exists e'', List.In e'' es /\ lab e'' = Spawn (thread e')).
      { clear - Hcontra.
        simpl in Hcontra.
        destruct Hcontra.
        eauto.
        right.
        apply List.in_map_iff in H.
        destruct H as [? [? ?]]; eexists; eauto.
      }
      destruct He'' as [? | [e'' [HIn Heq]]]; [destruct HpoWF; now eauto|].
      pose proof (po_spawn _ HpoWF _ _ Heq).
      specialize (Henum _ HIn).
      apply Hpo1.
      eapply trans;
        now eauto with Relations_db Po_db.
    Qed.

    (** ThreadPool invariant with respect to thread of event e' when
            thread of event e steps and the two events are not in [po]. *)
    Lemma no_po_gsoThread:
      forall e e' es tp tp'
        (Hneq: e <> e')
        (HpoWF: po_well_formed po)
        (Hpo1: ~ po e e')
        (Hpo2: ~ po e' e)
        (Henum: forall e'', List.In e'' es -> po e e'') 
        (Hstep: tp [thread e, List.map lab (e :: es) ]==> tp'),
        getThread (thread e') tp' = getThread (thread e') tp.
    Proof.
      intros.
      assert (Htid_neq: thread e <> thread e')
        by (eapply no_po_thread_neq; eauto).
      inv Hstep;
        try (erewrite gsoThread; now eauto).
      (** Spawn thread case*)
      erewrite! gsoThread; eauto.
      intros Hcontra; subst.
      eapply no_po_spawn_neq with (e' := e') (e := e);
        eauto.
      simpl (List.map lab (e :: es)).
      rewrite <- H0.
      apply List.in_or_app;
        simpl; now eauto.
    Qed.

    (** ** Basic Properties of program semantics *)
    Lemma step_gsoThread:
      forall e e' es tp tp'
        (Hneq: thread e <> thread e')
        (Hspawn:  ~ List.In (Spawn (thread e')) (List.map lab (e :: es)))
        (Hstep: tp [thread e, List.map lab (e :: es) ]==> tp'),
        getThread (thread e') tp' = getThread (thread e') tp.
    Proof.
      intros.
      inv Hstep;
        try (erewrite gsoThread; now eauto).
      (** Spawn thread case*)
      erewrite! gsoThread; eauto.
      intros Hcontra; subst.
      apply Hspawn.
      simpl (List.map lab (e :: es)).
      rewrite <- H0.
      apply List.in_or_app;
        simpl; now eauto.
    Qed.

    (** [step] is invariant to [updThread] when the thread updated is
                not the stepping thread or a thread spawned by the stepping thread *)
    Lemma step_updThread:
      forall tp i es tp' j c'
        (Hneq: i <> j)
        (Hspawn: ~List.In (Spawn j) es)
        (Hstep: tp [i, es]==> tp'),
        updThread j c' tp [i, es]==>
                  updThread j c' tp'.
    Proof.
      intros.
      inv Hstep.
      - simpl.
        erewrite updComm by eauto.
        econstructor; eauto.
        erewrite gsoThread by eauto.
        assumption.
      - simpl.
        erewrite updComm by eauto.
        econstructor 2; eauto.
        erewrite gsoThread by eauto;
          eassumption.
      - simpl.
        assert (j <> j0).
        { intros Hcontra.
          subst.
          clear - Hspawn.
          apply Hspawn; auto.
          eapply List.in_or_app; simpl;
            now eauto.
        }
        assert (j0 <> i)
          by (intros Hcontra;
              subst; congruence).
        assert (Hupd: updThread j0 c'' (updThread i c'0 tp) =
                      updThread i c'0 (updThread j0 c'' tp))
          by (erewrite updComm; eauto).
        rewrite Hupd.
        erewrite updComm by eauto.
        assert (Hupd': updThread j c' (updThread j0 c'' tp) =
                       updThread j0 c'' (updThread j c' tp))
          by (erewrite updComm; eauto).
        rewrite Hupd'.
        erewrite updComm by eauto.
        econstructor 3; eauto.
        erewrite gsoThread by eauto;
          eassumption.
        erewrite gsoThread by eauto;
          assumption.
    Qed.

    (** Spawned thread not in threadpool before spawning, but in threadpool after spawning *)
    Lemma step_spawn:
      forall tp tp' es i j
        (Hstep: tp [i, es]==> tp')
        (Hspawn: List.In (Spawn j) es),
        getThread j tp = None /\
        getThread j tp' <> None.
    Proof.
      intros.
      inv Hstep;
        try (exfalso; eapply concLabelsofE_no_spawn; now eauto).
      assert (j = j0).
      { clear - Hspawn.
        eapply List.in_app_or in Hspawn.
        destruct Hspawn as [?| HIn];
          [exfalso; eapply concLabelsofE_no_spawn;
           now eauto|].
        simpl in HIn.
        destruct HIn as [HIn | HIn];
          now inv HIn.
      }
      subst.
      split;
        [now auto| rewrite gssThread; now congruence].
    Qed.

    Lemma getThread_monotone:
      forall tp j c i es tp'
        (Hget: getThread j tp = Some c)
        (Hstep: tp [i, es]==> tp'),
      exists c',
        getThread j tp' = Some c'.
    Proof.
      intros.
      destruct (eq_dec i j).
      - subst.
        inv Hstep;
          try (eexists; erewrite gssThread;
               now eauto).
        destruct (eq_dec j j0); subst; [congruence|].
        eexists; erewrite gsoThread by eauto.
        erewrite gssThread; eauto.
      - inv Hstep;
          try (erewrite gsoThread by eauto; eauto).
        destruct (eq_dec j j0); subst; [congruence|].
        erewrite! gsoThread;
          now eauto.
    Qed.

    (** * Properties of combined program/execution steps *)

    (** Commuting steps *)
    Lemma commute_step_sc:
      forall tp Ex Ex' tp' es e' es' tp''
        (HstepSC: [tp, Ex] ==>sc [tp', Ex'])
        (Hstep: tp' [thread e', List.map lab (e' :: es')]==> tp'')
        (Henum: enumerate po es (e' :: es')%list)
        (Hdisjoint: Disjoint _ es Ex)
        (HminSC: forall e, e \in Ex -> sc e' e)
        (Hpo: forall e, e \in Ex -> ~ po e' e)
        (HpoWF: po_well_formed po)
        (HscPO: strict_partial_order sc)
        (Hposc: inclusion _ po sc),
      exists tp0,
        [tp, Union _ Ex es] ==>sc [tp0, Ex] /\
        [tp0, Ex] ==>sc [tp'', Ex'].
    Proof.
      intros.
      inv HstepSC.

      (** *** Useful facts in the proof *)
      assert (HIn0: In _ es0 e'0)
        by (destruct Henum0; eapply H; simpl; now auto).

      (** e'0 <> e' *)
      assert (Hneq_ev: e'0 <> e').
      { intros Hcontra; subst.
        apply Disjoint_sym in Hdisjoint.
        apply Disjoint_Union_r in Hdisjoint.
        inversion Hdisjoint as [Hdisjoint'].
        specialize (Hdisjoint' e').
        apply Hdisjoint'.
        pose proof (proj2 (proj1 Henum e') ltac:(simpl; auto)).
        pose proof (proj2 (proj1 Henum0 e') ltac:(simpl; auto)).
        eauto with Ensembles_DB.
      }

      (** ~ po e'0 e *)
      assert (Hnot_po1: ~po e'0 e').
      { specialize (HminSC e'0 ltac:(eauto with Ensembles_DB)).
        intros Hcontra.
        apply Hposc in Hcontra.
        pose proof (antisym _ HscPO _ _ Hcontra HminSC).
        subst.
        eapply (strict _ HscPO);
          now eauto.
      }

      (** Every element in es'0 is po-after e'0 by the spec of [enumerate]*)
      assert (Henum_spec: forall e'' : id, List.In e'' es'0 -> po e'0 e'')
        by (intros;
            eapply @enumerate_spec' with (es := es0) (es' := nil);
            simpl; eauto with Po_db Relations_db).

      (** The state of (thread e') is unchanged by the step of (thread e'0) *)
      assert (Hget_e': getThread (thread e') tp'= getThread (thread e') tp)
        by (eapply no_po_gsoThread with (e := e'0) (e' := e'); eauto).
  
      (** *** First prove commutativity for program steps *)
      assert (Hprog_step: exists tp0, tp [thread e', List.map lab (e' :: es')]==> tp0 /\
                                 tp0 [thread e'0, List.map lab (e'0 :: es'0)]==> tp'').
      { inv Hstep.
        - exists (updThread (thread e') c' tp).
          split.
          + simpl. rewrite <- H0.
            econstructor; eauto.
            rewrite <- Hget_e'.
            assumption.
          + simpl.
            apply step_updThread;
              eauto using no_po_thread_neq, no_po_spawn_neq.
        - exists (updThread (thread e') c' tp).
          split.
          + simpl. rewrite <- H0.
            econstructor 2; eauto.
            rewrite <- Hget_e'.
            assumption.
          + simpl.
            apply step_updThread;
              eauto using no_po_thread_neq, no_po_spawn_neq.
        - exists (updThread j c'' (updThread (thread e') c' tp)).
          (** proof that j was not a valid thread at tp *)
          assert (Hget_j': getThread j tp = None).
          { destruct (getThread j tp) eqn:Hgetj; auto.
            destruct (getThread_monotone tp j _ _ _ tp' Hgetj Hstep0) as [? ?];
              now congruence.
          }
          split.
          + simpl. rewrite <- H0.
            econstructor 3; eauto.
            rewrite <- Hget_e'.
            assumption.
          + simpl.
            (** [thread e'0] <> j because getThread (thread e'0) tp = Some _ by the fact
                that it steps and getThread j tp = None as proved *)            
            assert (thread e'0 <> j)
              by (intros ?; subst; inv Hstep0; now congruence).
            (** Moreover, it cannot be that the step from [thread e'0] has an event [Spawn j]
                because that would imply that it spawned thread j but we know that
                getThread j tp' = None which leads to a contradiction *)
            assert (~ List.In (Spawn j) (lab e'0 :: List.map lab es'0)).
            { intros Hcontra.
              eapply step_spawn in Hcontra; eauto.
              destruct Hcontra;
                congruence.
            }
            (** Now we can use the fact that the update of the threadpool on
                thread j does not affect the step of thread e'0 *)
            eapply step_updThread;
              eauto using no_po_thread_neq, no_po_spawn_neq.
            (** Likewise for the step of thread e' *)
            eapply step_updThread;
              eauto using no_po_thread_neq, no_po_spawn_neq.
      }
      destruct Hprog_step as [tp0 [Hprog_stepe' Hprog_step0']].
      exists tp0.
      (** To prove that there is an sc step we also need to prove that
          the events used by the program steps are sc-minimal in the execution *)
      assert (Hmin_e': In _ (Order.min sc (Union _ (Union _ Ex' es0) es)) e').
      {
        (** We know by the fact that e' is in the head of the enumeration of es
        it is the po-minimal element in es, and hence it must also be sc-minimal
        in es as po is included in sc *) 
        assert (Hmin_1: In _ (Order.min sc es) e').
        { constructor.
          eapply Henum;
            now (simpl; auto).
          intros (y & Hy & Hcontra).
          eapply Henum in Hy.
          simpl in Hy.
          destruct Hy as [Hy | Hy];
            [subst; eapply strict;
             now eauto with Relations_db|].
          eapply enumerate_hd in Henum; eauto with Relations_db Po_db.
          apply Hincl in Henum.
          pose proof (antisym _ ltac:(eauto) _ _ Hcontra Henum);
            subst.
          eapply strict;
            now eauto.
        }
        econstructor.
        constructor 2.
        eapply Henum; simpl;
          now eauto.
        intros (emin & HIn & Hcontra).
        eapply In_Union_inv in HIn.
        destruct HIn as [HIn | HIn].
        - (** Case emin is in Union Ex' es0 *)
          (** We know that every element of Union Ex' es0 is sc-smaller than e
            by HminSC *)
          specialize (HminSC _ HIn).
          pose proof (antisym _ ltac:(eauto) _ _ Hcontra HminSC);
            subst.
          eapply strict;
            eauto with Relations_db Po_db.
        - (** Case emin is in es *)
          (** By the fact we just proved (Hmin_1) that e' is sc-minimal in es *)
          inversion Hmin_1 as [_ Hmin_contra].
          apply Hmin_contra.
          eexists; split;
            now eauto.
      }
      split;
        econstructor;
        eauto with Ensembles_DB.
    Qed.

    Lemma same_set_eq:
      forall {A:Type} (U1 U2: Ensemble A)
        (Hsame: U1 <--> U2),
        U1 = U2.
    Proof.
      intros.
      eapply FunctionalExtensionality.functional_extensionality.
      intros.
      inv Hsame.
      eapply Axioms.prop_ext.
      specialize (H x).
      specialize (H0 x).
      split;
        now eauto with Ensembles_DB.
    Qed.

    Lemma commute_steps_sc:
      forall n tp Ex Ex' tp' es e' es' tp''
        (HstepSC: [tp, Ex] ==>{n} [tp', Ex'])
        (Hstep: tp' [thread e', List.map lab (e' :: es')]==> tp'')
        (Henum: enumerate po es (e' :: es')%list)
        (Hdisjoint: Disjoint _ es Ex)
        (HminSC: forall e, e \in Ex -> sc e' e)
        (Hpo: forall e, e \in Ex -> ~ po e' e)
        (HpoWF: po_well_formed po)
        (HscPO: strict_partial_order sc)
        (Hposc: inclusion _ po sc),
      exists tp0,
        [tp, Union _ Ex es] ==>sc [tp0, Ex] /\
        [tp0, Ex] ==>{n} [tp'', Ex'].
    Proof.
      intros.
      generalize dependent tp.
      generalize dependent Ex.
      induction n; intros.
      - (** Base case *)
        inv HstepSC.
        exists tp''.
        split; eauto using Step0.
        econstructor;
          eauto with Ensembles_DB.
        constructor.
        constructor 2.
        eapply Henum;
          simpl; now auto.
        intros (y & HIn & Hsc).
        eapply In_Union_inv in HIn.
        destruct HIn as [HIn | HIn].
        + specialize (HminSC _ HIn).
          pose proof (antisym _ ltac:(eauto) _ _ Hsc HminSC);
            subst.
          eapply strict;
            eauto with Relations_db Po_db.
        + eapply Henum in HIn.
          simpl in HIn.
          destruct HIn as [HIn | HIn];
            [subst; eapply strict;
             now eauto with Relations_db|].
          eapply enumerate_hd in Henum; eauto with Relations_db Po_db.
          apply Hposc in Henum.
          pose proof (antisym _ ltac:(eauto) _ _ Hsc Henum);
            subst.
          eapply strict;
            now eauto.
      - (** Inductive Case *)
        inversion HstepSC as [|? ? ? tp0 Ex0 ? ? ?]; subst.
        clear HstepSC.
        assert (Hdisjoint0: Disjoint id es Ex0) by admit.
        assert (HminSC0: forall e, In id Ex0 e -> sc e' e) by admit.
        assert (Hpo0: forall e, In _ Ex0 e -> ~ po e' e) by admit.
        (** By inductive hypothesis*)
        destruct (IHn _ Hdisjoint0 HminSC0 Hpo0 _ HRstepN') as [tp1 [Hstep1 HRstepN'']].
        clear HRstepN'.
        (** and by applying the commutativity lemma *)
        inversion Hstep1; subst.
        (** prove that the sets es0 and es are the same *)
        eapply Disjoint_Union_eq in H0; eauto with Ensembles_DB.
        eapply same_set_eq in H0; subst; eauto.
        assert (exists tp2, [tp, Union _ Ex es] ==>sc [tp2, Ex] /\
                       [tp2, Ex] ==>sc [tp1, Ex0]).
        { eapply commute_step_sc; eauto.
          (** e'0 is sc-minimal in Ex *)
          intros e HIn.
          (* Return here *)
          

      (* Notation " c '[' ls ']'-->' c' " := *)      (*   (tstep genv po sc tp1 Ex1 tp2 Ex2) (at level 40). *)
          
    Lemma commute_sc:
      forall n tp Ex es e' es' tp' Ex' tp''
        (Hsc_steps: [tp, Ex] ==>{n} [tp', Ex'])
        (Hp_step: tp' [thread e', List.map lab (e' :: es')]==> tp'')
        (Henum: enumerate po es (e' :: es'))
        (Hmin: e' \in Execution.min sc (Union _ Ex es))
        (Hincl: inclusion id po sc)
        (Hdis: Disjoint _ Ex es),
        [tp, Union _ Ex es] ==>{S n} [tp'', Ex'].
    Proof.
      intro n.
      intros.

      induction n; intros.
      - (** Base case *)
        inv Hsc_steps.
        eapply StepN with (x1 := tp') (y1 := Union _ Ex' es)
                                      (x2 := tp'') (y2 := Ex');
          simpl.
        eapply @RStep; eauto.
        now constructor.
      - (** Inductive case *)
        inversion Hsc_steps as [|? ? ? tp0 Ex0 ? ?]; subst.
        assert (e' \in (Execution.min sc (Union _ Ex0 es)))
          by admit.
        assert (Disjoint _ Ex0 es)
          by admit.
        specialize (IHn _ _ _ _ _ _ _ _ HRstepN' Hp_step Henum H Hincl H0).




        specialize (IHn _ 
                        
        econstructor.
        
    Lemma step_po_sim:
      forall n Ex tp1 Ex1 tp2 Ex2 tp1' Ex1'
        (Hsim: sim n Ex tp1 Ex1 tp2 Ex2)
        (Hstep_po: (tp1, Ex1) ==>po (tp1', Ex1')),
      exists G2',
        sim n Ex tp1' Ex1' tp2 G2'.
    Proof.
      intros.
      assert (HstepsSC := steps _ _ _ _ _ _ Hsim).
      inv Hstep_po.


      Lemma steps_sc_split_at:
        forall n tp1 Ex1 tp2 Ex2 e
          (Hsteps_sc: (tp1, Ex1) ==>{n} (tp2, Ex2))
....          


      


    (* Goal *)
    Theorem axiomaticToIntermediate:
      forall n tp tp' Ex
        (Hexec: Rsteps cstep genv po po n (tp, Ex) (tp', Empty_set _))
        (Hvalid: validSC Ex po sc),
        Rsteps cstep genv po sc n (tp, Ex) (tp', Empty_set _).
    Proof.
      Admitted.

  