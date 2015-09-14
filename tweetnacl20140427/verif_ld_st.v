Require Import floyd.proofauto.
Local Open Scope logic.
Require Import List. Import ListNotations.
Require Import general_lemmas.

Require Import split_array_lemmas.
Require Import fragments.
Require Import ZArith. 
Require Import tweetNaclBase.
Require Import Salsa20.
Require Import verif_salsa_base.
Require Import tweetnaclVerifiableC.

Require Import spec_salsa.

Opaque Snuffle20. Opaque Snuffle.Snuffle. Opaque prepare_data. 
Opaque core_spec. Opaque fcore_result.
Opaque crypto_core_salsa20_spec. Opaque crypto_core_hsalsa20_spec.

Lemma L32_spec_ok: semax_body SalsaVarSpecs SalsaFunSpecs
       f_L32 L32_spec.
Proof.
start_function.
name x' _x.
name c' _c.
forward. entailer. apply prop_right.
assert (W: Int.zwordsize = 32). reflexivity.
assert (U: Int.unsigned Int.iwordsize=32). reflexivity.
remember (Int.ltu c' Int.iwordsize) as d. symmetry in Heqd.
destruct d; simpl. 
Focus 2. apply ltu_false_inv in Heqd. rewrite U in *. omega.
clear Heqd. split; trivial.
remember (Int.ltu (Int.sub (Int.repr 32) c') Int.iwordsize) as z. symmetry in Heqz.
destruct z.
Focus 2. apply ltu_false_inv in Heqz. rewrite U in *. 
         unfold Int.sub in Heqz. 
         rewrite (Int.unsigned_repr 32) in Heqz. 
           rewrite Int.unsigned_repr in Heqz. omega. rewrite int_max_unsigned_eq; omega.
           rewrite int_max_unsigned_eq; omega.
simpl; split; trivial. split; trivial.
apply ltu_inv in Heqz. unfold Int.sub in *.
  rewrite (Int.unsigned_repr 32) in *; try (rewrite int_max_unsigned_eq; omega).
  rewrite Int.unsigned_repr in Heqz. 2: rewrite int_max_unsigned_eq; omega.
  unfold Int.rol, Int.shl, Int.shru. rewrite or_repr. 
  assert (Int.unsigned c' mod Int.zwordsize = Int.unsigned c').
    apply Zmod_small. rewrite W; omega.
  rewrite H0, W. f_equal. f_equal. f_equal.
  rewrite Int.unsigned_repr. 2: rewrite int_max_unsigned_eq; omega.
  rewrite Int.and_mone. trivial.
Qed.

Lemma ld32_spec_ok: semax_body SalsaVarSpecs SalsaFunSpecs
       f_ld32 ld32_spec.
Proof.
start_function.
name x' _x.
destruct B as (((b0, b1), b2), b3). simpl.
specialize Byte_max_unsigned_Int_max_unsigned; intros BND.
assert (RNG3:= Byte.unsigned_range_2 b3).
assert (RNG2:= Byte.unsigned_range_2 b2).
assert (RNG1:= Byte.unsigned_range_2 b1).
assert (RNG0:= Byte.unsigned_range_2 b0).
forward.
forward v.
forward u.
forward z.
forward q.
forward p.
forward. 
  entailer.
  apply prop_right. unfold Znth in H3. simpl in H3. inv H3. clear - BND RNG0 RNG1 RNG2 RNG3.   
  rewrite shift_two_8, shift_two_8_2, shift_two_8_3.
  assert (WS: Int.zwordsize = 32). reflexivity.
  assert (TP: two_p 8 = Byte.max_unsigned + 1). reflexivity.
  assert (BMU: Byte.max_unsigned = 255). reflexivity.
  repeat rewrite Int.shifted_or_is_add; try repeat rewrite Int.unsigned_repr; try omega.
 
  repeat rewrite Z.mul_add_distr_r. f_equal. omega.
  rewrite TP, BMU, Z.mul_add_distr_l, int_max_unsigned_eq. omega.
  rewrite TP, BMU, Z.mul_add_distr_l, int_max_unsigned_eq. omega.
  rewrite TP, BMU, Z.mul_add_distr_l, int_max_unsigned_eq. omega.
Qed.

Lemma ST32_spec_ok: semax_body SalsaVarSpecs SalsaFunSpecs
       f_st32 st32_spec.
Proof. 
start_function.
name x' _x.
name u' _u.
normalize. intros l. normalize. rename H into Hl.
remember (littleendian_invert u) as U. destruct U as [[[u0 u1] u2] u3].
  forward_for_simple_bound 4 (EX i:Z, 
  (PROP  ()
   LOCAL (temp _x x; temp _u (Vint (iterShr8 u (Z.to_nat i))))
   SEP (`(EX ll:_, !!(
                     ll = firstn (Z.to_nat i) (map Vint (map Int.repr (map Byte.unsigned ([u0;u1;u2;u3]))))
                         ++ skipn (Z.to_nat i) l)
            && data_at Tsh (Tarray tuchar 4 noattr) ll x)))).
{ entailer. apply (exp_right l); entailer. }
{ rename H into I. normalize. intros LST. normalize.
  forward. forward v. subst v.
  entailer. apply (exp_right (upd_reptype_array tuchar i
     (firstn (Z.to_nat i)
        [Vint (Int.repr (Byte.unsigned u0));
        Vint (Int.repr (Byte.unsigned u1));
        Vint (Int.repr (Byte.unsigned u2));
        Vint (Int.repr (Byte.unsigned u3))] ++ skipn (Z.to_nat i) l)
     (Vint (Int.zero_ext 8 (iterShr8 u (Z.to_nat i)))))).
  entailer.
  apply prop_right. rewrite Z.add_comm, Z2Nat.inj_add; try omega.
        simpl. 
        split; trivial.
        destruct l; simpl in Hl. omega.
        destruct l; simpl in Hl. omega.
        destruct l; simpl in Hl. omega.
        destruct l; simpl in Hl. omega.
        destruct l; simpl in Hl. 2: omega. clear Hl.
        unfold upd_reptype_array.
        assert (ZW: Int.zwordsize = 32) by reflexivity.
        assert (EIGHT: Int.unsigned (Int.repr 8) = 8). apply Int.unsigned_repr. rewrite int_max_unsigned_eq; omega.
        inv HeqU. clear - ZW EIGHT I.
        destruct (zeq i 0); subst; simpl. f_equal. f_equal.
        { rewrite Byte.unsigned_repr.              
            rewrite (Fcore_Zaux.Zmod_mod_mult _ (2^8) (2^8)). 2: cbv; trivial. 2: cbv; intros; discriminate.
            rewrite (Fcore_Zaux.Zmod_mod_mult _ (2^16) (2^8)). 2: cbv; trivial. 2: cbv; intros; discriminate.
            rewrite <- (Int.zero_ext_mod 8).
              rewrite Int.repr_unsigned; trivial.
              rewrite ZW; omega.
          assert (0 <= ((Int.unsigned u mod Z.pow_pos 2 24) mod Z.pow_pos 2 16) mod Z.pow_pos 2 8 < Byte.modulus).
            apply Z_mod_lt. cbv; trivial. 
            unfold Byte.max_unsigned. omega. }
        destruct (zeq i 1); subst; simpl. f_equal. f_equal. f_equal.
        { rewrite Byte.unsigned_repr.  
          Focus 2. assert (0 <= (Int.unsigned u mod Z.pow_pos 2 24) mod Z.pow_pos 2 16 / Z.pow_pos 2 8 < Byte.modulus).
                   2: unfold Byte.max_unsigned; omega.
                   split. apply Z_div_pos. cbv; trivial. apply Z_mod_lt. cbv; trivial.
                   apply Zdiv_lt_upper_bound. cbv; trivial. apply Z_mod_lt. cbv; trivial.
          apply Int.same_bits_eq. rewrite ZW; intros.
          rewrite Int.bits_zero_ext, Int.testbit_repr; try apply H. 
          rewrite (Z.div_pow2_bits _ 8); try omega.
          rewrite (Int.Ztestbit_mod_two_p 16); try omega.
          rewrite (Int.Ztestbit_mod_two_p 24); try omega.
          rewrite Int.bits_shru; try omega. rewrite EIGHT, ZW, Ztest_Inttest.
          remember (zlt i 8). 
          destruct s. repeat rewrite zlt_true. trivial. omega. omega. omega.
          rewrite zlt_false. trivial. omega. }
        destruct (zeq i 2); subst; simpl. f_equal. f_equal. f_equal.
          f_equal.
        { rewrite Byte.unsigned_repr.  
          Focus 2. assert (0 <= Int.unsigned u mod Z.pow_pos 2 24 / Z.pow_pos 2 16 < Byte.modulus).
                   2: unfold Byte.max_unsigned; omega.
                   split. apply Z_div_pos. cbv; trivial. apply Z_mod_lt. cbv; trivial.
                   apply Zdiv_lt_upper_bound. cbv; trivial. apply Z_mod_lt. cbv; trivial.
          apply Int.same_bits_eq. rewrite ZW; intros.
          rewrite Int.bits_zero_ext, Int.testbit_repr; try apply H. 
          rewrite Int.bits_shru; try omega. rewrite EIGHT, ZW.
          rewrite (Z.div_pow2_bits _ 16); try omega.
          rewrite (Int.Ztestbit_mod_two_p 24); try omega.
          rewrite Ztest_Inttest.
          remember (zlt i 8). 
          destruct s. repeat rewrite zlt_true. rewrite Int.bits_shru, EIGHT, ZW.
              rewrite zlt_true. rewrite <- Z.add_assoc. reflexivity. omega. omega. omega. omega.
          rewrite zlt_false. trivial. omega. }
        destruct (zeq i 3); subst; simpl. f_equal. f_equal. f_equal. f_equal.
          f_equal.
        { rewrite Byte.unsigned_repr.  
          Focus 2. assert (0 <= Int.unsigned u / Z.pow_pos 2 24 < Byte.modulus).
                   2: unfold Byte.max_unsigned; omega.
                   split. apply Z_div_pos. cbv; trivial. apply Int.unsigned_range. 
                   apply Zdiv_lt_upper_bound. cbv; trivial. apply Int.unsigned_range. 
          apply Int.same_bits_eq. rewrite ZW; intros.
          rewrite Int.bits_zero_ext, Int.testbit_repr; try apply H. 
          rewrite Int.bits_shru; try omega. rewrite EIGHT, ZW.
          rewrite (Z.div_pow2_bits _ 24); try omega.
          rewrite Ztest_Inttest.
          remember (zlt i 8). 
          destruct s. rewrite zlt_true. rewrite Int.bits_shru, EIGHT, ZW.
              rewrite zlt_true. rewrite Int.bits_shru, EIGHT, ZW. 
              rewrite zlt_true. repeat rewrite <- Z.add_assoc. reflexivity. omega. omega. omega. omega. omega.
          rewrite Int.bits_above. trivial. omega. }
        omega. }
  forward.
Qed.

(*
Definition L32_specZ :=
  DECLARE _L32
   WITH x : int, c: int
   PRE [ _x OF tuint, _c OF tint ]
      PROP () (*c=Int.zero doesn't seem to satisfy spec???*)
      LOCAL (temp _x (Vint x); temp _c (Vint Int.zero))
      SEP ()
  POST [ tuint ] 
     PROP (True)
     LOCAL ()
     SEP ().

Definition LDZFunSpecs : funspecs := 
  L32_specZ::nil.

Lemma L32_specZ_ok: semax_body SalsaVarSpecs LDZFunSpecs
       f_L32 L32_specZ.
Proof.
start_function.
name x' _x.
name c' _c.
forward. entailer. apply prop_right.
assert (W: Int.zwordsize = 32). reflexivity.
assert (U: Int.unsigned Int.iwordsize=32). reflexivity.
(*remember (Int.eq c' Int.zero) as z.
  destruct z. apply binop_lemmas.int_eq_true in Heqz. subst. simpl. *)
remember (Int.ltu (Int.repr 32) Int.iwordsize) as d. symmetry in Heqd.
destruct d; simpl. 
Focus 2. apply ltu_false_inv in Heqd. rewrite U in *. rewrite Int.unsigned_repr in Heqd. 2: rewrite int_max_unsigned_eq; omega.
clear Heqd. split; trivial.
remember (Int.ltu (Int.sub (Int.repr 32) c') Int.iwordsize) as z. symmetry in Heqz.
destruct z.
Focus 2. apply ltu_false_inv in Heqz. rewrite U in *. 
         unfold Int.sub in Heqz. 
         rewrite (Int.unsigned_repr 32) in Heqz. 
           rewrite Int.unsigned_repr in Heqz. omega. rewrite int_max_unsigned_eq; omega.
           rewrite int_max_unsigned_eq; omega.
simpl; split; trivial. split; trivial.
apply ltu_inv in Heqz. unfold Int.sub in *.
  rewrite (Int.unsigned_repr 32) in *; try (rewrite int_max_unsigned_eq; omega).
  rewrite Int.unsigned_repr in Heqz. 2: rewrite int_max_unsigned_eq; omega.
  unfold Int.rol, Int.shl, Int.shru. rewrite or_repr. 
  assert (Int.unsigned c' mod Int.zwordsize = Int.unsigned c').
    apply Zmod_small. rewrite W; omega.
  rewrite H0, W. f_equal. f_equal. f_equal.
  rewrite Int.unsigned_repr. 2: rewrite int_max_unsigned_eq; omega.
  rewrite Int.and_mone. trivial.
Qed.
*)
