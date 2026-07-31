  module module_pbl3d_my

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !                                                                         !
    ! Purpose: 1) Calculates turbulent fluxes of momentum, heat and moisture  !
    !                                                                         !
    !          2) Calculates tendencies due to 3D turbulent mixing            !
    !                                                                         !
    ! Author: Pedro A. Jimenez & Timothy W. Juliano                           !
    !                                                                         !
    ! Methods: Uses the Mellor and Yamada turbulence closure model            !
    !                                                                         !
    ! References: M73: Mellor, G. L., 1973: Analytic prediction of the        !
    !                  properties of stratified planetary surface layers. J.  !
    !                  Atmos. Sci., 30, 1061-1069.                            !
    !                                                                         !
    !             MY74: Mellor, G. L., and T. Yamada, 1974: A hierarchy of    !
    !                   turbulence closure models for planetary boundary      !
    !                   layers. J. Atmos. Sci., 31, 1791-1806.                !
    !                                                                         !
    !             YM75: Yamada, T., and G. Mellor, 1975: A simulation of the  !
    !                   Wangara atmospheric boundary layer data. J. Atmos.    !
    !                   Sci., 32, 2309-2329.                                  !
    !                                                                         !
    !              Y75: Yamada, T., The critical richardson number and the    !
    !                   ratio of the eddy transport coefficients obtained     !
    !                   from a turbulence closure model. JAS, 32, 926 - 933   !
    !                                                                         !
    !             MY82: Mellor, G. L., and T. Yamada, 1982: Development of a  !
    !                   turbulent closure model for geophysical fluid         !
    !                   problems. Rev. Geophys.                               !
    !                   Space Phys., 20, 851-875.                             !
    !                                                                         !
    !              Y83: Yamada, T., 1983: Simulations of nocturnal drainage   !
    !                   flows by a q2/l turbulence closure model              !
    !                                                                         !
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    use, intrinsic :: iso_fortran_env

    use module_model_constants, only: KARMAN, G, P608, T0, CP, RCP
    use module_state_description, only: p_qc, p_qr, p_qi, p_qs, p_qg, p_qnc, p_qnr, p_qni, p_qnwfa, p_qnifa, param_first_scalar
    use module_big_step_utilities_em, only: grid_config_rec_type

    implicit none

    private

    public :: Set_init_turb_state_my, Calc_turb_fluxes_my

    real, parameter :: G_OVER_TREF = G / T0
    real, parameter :: DWIND_DZ_MIN = 1.0E-10
    real, public    :: Q_SQ_MIN, TURB_FLUX_MIN
    logical, parameter :: USE_HIGH_ORDER = .true.

      ! Safeguards for the full 3D closure (pbl3d_opt = 2) only. The A matrix of the
      ! algebraic second-moment system has the structure A = (1/tau) I + S, where
      ! tau = l / q is the turbulence relaxation time scale and S holds the mean
      ! gradient terms. It degenerates when |S| tau ~ 1, which is exactly where the
      ! weak-equilibrium (algebraic) assumption behind the closure itself breaks down.
      ! The safeguards below therefore act on l, not on the matrix entries.
      !
      ! SK_EPS_MAX: largest S k / eps admitted by the algebraic closure. Durbin (1996,
      !   Int. J. Heat Fluid Flow 17, 89-90) bounds the turbulence time scale by the
      !   strain rate for exactly this reason; the value is ~2x the homogeneous shear
      !   equilibrium value S k / eps ~ 3.3, so the limiter is inactive in equilibrium
      !   shear layers and only engages in the strong-strain regime.
      !   With k = q^2 / 2 and eps = q^3 / (b_1 l) this becomes l <= (2 SK_EPS_MAX / b_1) q / |S|,
      !   i.e. the shear analogue of the buoyancy limit l <= N_TAU_MAX q / N applied by
      !   Calc_l_master_algebra (see N_TAU_MAX below).
      !   Set from the namelist (pbl3d_sk_eps_max, default 6.0) rather than fixed, because
      !   it is the binding control on l wherever the raw S k / eps exceeds it, which offline
      !   estimates put at every point of the nocturnal boundary layer, slope drainage and
      !   low level jet regimes. Homogeneous shear equilibrium is about 3.3, so the default
      !   is deliberately about twice as permissive. COND_MAX is deliberately NOT exposed:
      !   with l0 fixed (pbl3d_l0_opt = 1) the median cond(A) is 10-400, eight orders of
      !   magnitude inside the limit, so there is nothing to scan.
      !
      ! N_TAU_MAX: largest N tau = N l / q admitted, i.e. the buoyancy limit l <= N_TAU_MAX q / N
      !   in stable stratification. This is the stratification counterpart of SK_EPS_MAX and
      !   rests on the same weak-equilibrium argument: an eddy of size l and velocity q turns
      !   over in tau = l / q, and buoyancy destroys it in 1 / N, so N tau > 1 describes an
      !   eddy that cannot exist. Deardorff (1980, Boundary-Layer Meteorol. 18, 495-527) sets
      !   l = 0.76 sqrt(e) / N under stable stratification; with e = q^2 / 2 that is
      !   l = 0.53 q / N, hence the default.
      !   It is applied in Calc_l_master_algebra, i.e. to l_master itself, not as a local
      !   fix-up inside the solver, because it is part of how the length scale is defined:
      !   pbl3d_l_opt = 2 (MYNN, l_f = alpha_2 q / N) and pbl3d_l_opt = 3 (Messinger,
      !   l_d = c_r q / N) already carry exactly this limit. pbl3d_l_opt = 1 (MY74) was the
      !   only branch without one, even though the comments here and in Diagnose_fluxes have
      !   always claimed otherwise.
      !   Why it is needed: q and l are computed by independent routes and nothing couples
      !   them. q_sq is a local production/dissipation balance and correctly collapses to
      !   Q_SQ_MIN in laminar air; l = l0 kappa z / (kappa z + l0) is geometric and asymptotes
      !   to l0 (order 30 m) all the way to the model lid. Above the boundary layer that gives
      !   tau = l / q ~ 8600 s against a buoyancy period of ~500 s, so N tau ~ 100 and the
      !   algebraic system is being solved two orders of magnitude outside its validity range.
      !   In level-2 equilibrium the limit is inert: substituting l = N_TAU_MAX q / N into
      !   q^2 = b_1 l^2 S^2 (1 - Rif) Sm makes it bind only above Ri ~ O(1), far beyond the
      !   Ri = 0.195 cutoff where the closure already returns no turbulence. It therefore acts
      !   only where l and q have genuinely decoupled, which is what it is for.
      !   Set from the namelist (pbl3d_n_tau_max, default 0.53); a very large value disables it.
    real,    public    :: SK_EPS_MAX, N_TAU_MAX
    real,    parameter :: STRAIN_MIN = 1.0E-10   ! avoids 0/0 in the strain limiter
    real,    parameter :: COND_MAX   = 1.0E8     ! largest admitted condition number of A
    real,    parameter :: L_BACKOFF  = 0.5       ! l reduction factor per escalation step
    integer, parameter :: MAX_SOLVE_ATTEMPTS = 6
    integer, parameter :: N_PSD_BISECT = 20      ! bisection steps of the covariance shrink

    integer, parameter :: SP = REAL32
    integer, parameter :: DP = REAL64
    integer, parameter :: SOLVER_PREC = DP
    integer, parameter :: WORKING_PREC = SP

      ! Model constants
    real         :: a_1, b_2, c_1, c_2, c_3, alpha, lambda
    real, public :: a_2, b_1

      ! For the level 2 model
    real :: rif_c, rf1, rf2, cm, ch2
    real :: fac1, fac2, fac3, fac4

    integer, parameter :: I_TO_TEST = 4, J_TO_TEST = 4, K_TO_TEST = 3

  contains

    subroutine Calc_turb_fluxes_my (config_flags, dz, z_at_mass, z_at_w, u, v, w, th, th2, qv, thetav, tsk, t2, q2, psfc, rho, ust, hfx, qfx, rmol, &
              du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, dqv_dx, dqv_dy, dqv_dz, dthetav_dx, dthetav_dy, dthetav_dz, &
              dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz, itimestep, ss, n_tracer, q_sq, q_sq_prog, &
              Psig_bl, l_master, l_master_at_mass, l_boulac, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, &
              turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_uqv, &
              turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, turb_flux_uqc, turb_flux_vqc, &
              turb_flux_wqc, turb_flux_uqr, turb_flux_vqr, turb_flux_wqr, turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, &
              turb_flux_uqs, turb_flux_vqs, turb_flux_wqs, turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, turb_flux_uqnc, turb_flux_vqnc, &
              turb_flux_wqnc, turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_wqni, &
              turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa, &
              msfux, msfuy, msfvx, msfvy, msftx, msfty, xland, pblh, &
              pbl3d_t1_ratio, pbl3d_t2_steps, pbl3d_t3_flags, pbl3d_sk_eps, pbl3d_n_tau, pbl3d_cond_a, pbl3d_qv2, &
              dx, dy, rdx, rdy, dn, dnw, rdz, dt, id, rdzw, fnm, fnp, cf1, cf2, cf3, zx, zy, mut, c1h, c2h, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Calculates turbulent fluxes                                  !
      !                                                                       !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                         !
      !                                                                       !
      ! Method: Mellor and Yamada model                                       !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags
      integer, intent(in) :: itimestep, id, ss, n_tracer

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: dz, z_at_mass, z_at_w, u, v, &
          w, th, th2, qv, rho, zx, zy, rdz, rdzw
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq, q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: pbl3d_t1_ratio, pbl3d_t2_steps, &
                                                                     pbl3d_t3_flags, pbl3d_sk_eps,   &
                                                                     pbl3d_n_tau, pbl3d_cond_a, pbl3d_qv2
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)   :: du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, &
          dw_dx, dw_dy, dw_dz, dthetav_dx, dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, dqv_dz, dqc_dz, dqr_dz,    &
          dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: l_master, l_master_at_mass, l_boulac
      real, dimension (ims:ime, jms:jme),          intent (in)    :: msfux, msfuy, msfvx, msfvy, msftx, msfty
      real, dimension (ims:ime, jms:jme),          intent (in)    :: tsk, t2, thetav, q2, psfc, ust, hfx, qfx, rmol, xland
      real, dimension (ims:ime, jms:jme),          intent (inout) :: pblh, Psig_bl
      real, dimension (ims:ime, jms:jme),          intent (in)    :: mut
      real, dimension (kms:kme),                   intent (in)    :: c1h, c2h
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: turb_flux_u2, turb_flux_v2, turb_flux_w2,  &
          turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
          turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta,  &
          turb_flux_wtheta, turb_flux_uqc, turb_flux_vqc, turb_flux_wqc, turb_flux_uqr, turb_flux_vqr,          &
          turb_flux_wqr, turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, turb_flux_uqs, turb_flux_vqs,             &
          turb_flux_wqs, turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, turb_flux_uqnc, turb_flux_vqnc,           &
          turb_flux_wqnc, turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, turb_flux_uqni, turb_flux_vqni,       &
          turb_flux_wqni, turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, turb_flux_uqnifa,               &
          turb_flux_vqnifa, turb_flux_wqnifa
      real, dimension (kms:kme),                   intent (in)    :: fnm, fnp, dn, dnw
      real,                                        intent (in)    :: dx, dy, rdx, rdy, cf1, cf2, cf3, dt
      integer,                                     intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte

        ! Local vars
      logical, parameter :: DEBUG = .false.
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf

        ! Diagnose PBL height
      call Diagnose_pbl_height (thetav, q_sq, z_at_w, dz, xland, pblh, ids, ide, jds, jde, kds, kde, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Calculate scale-aware tapering function
      call Calc_scale_aware (config_flags%pbl3d_scale_aware, dx, dy, msftx, msfty, pblh, Psig_bl, ids, ide, jds, jde, kds, kde, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      if (config_flags%pbl3d_opt < 2) then  ! PBL approx analytical solution only
        call Calc_fluxes_pbl_approx (config_flags, ss, Psig_bl, l_master, l_boulac, du_dz, dv_dz, dthetav_dz, dqv_dz, &
            dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz, &
            th2, qv, dn, dnw, fnm, fnp, dx, dy, dz, z_at_w, zx, zy, msftx, msfty, rdz, rdzw, cf1, cf2, cf3, dt, id, &
            ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts,    &
            jte, kts, kte, q_sq, q_sq_prog, turb_flux_u2, turb_flux_v2, turb_flux_w2,     &
            turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                 &
            turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_uqv,    &
            turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, &
            turb_flux_uqc, turb_flux_vqc, turb_flux_wqc, turb_flux_uqr, turb_flux_vqr, turb_flux_wqr, &
            turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, turb_flux_uqs, turb_flux_vqs, turb_flux_wqs, &
            turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, turb_flux_uqnc, turb_flux_vqnc, turb_flux_wqnc, &
            turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_wqni, &
            turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa, &
            u, v, w, thetav, rho, ust, hfx, qfx, rmol)
      else if (config_flags%pbl3d_opt == 2) then  ! Full 3D numerical solution
        call Calc_fluxes (config_flags, id, config_flags%specified, q_sq, q_sq_prog, Psig_bl, l_master, l_boulac, &
            du_dx, du_dy, du_dz, dv_dx, dv_dy,   &
            dv_dz, dw_dx, dw_dy, dw_dz, dthetav_dx, dthetav_dy, dthetav_dz, dqv_dx, dqv_dy,  &
            dqv_dz, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw,    &
            turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v,        &
            turb_flux_theta2_v, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,        &
            turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, th2, thetav, qv, rho, hfx, qfx, rmol, u, v, ust,  &
            pbl3d_t1_ratio, pbl3d_t2_steps, pbl3d_t3_flags, pbl3d_sk_eps, pbl3d_n_tau, pbl3d_cond_a, pbl3d_qv2,       &
            dz, rdzw, z_at_w, fnm, fnp, cf1, cf2, cf3, dn, dnw, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme,  &
            its, ite, jts, jte, kts, kte)
      end if

      if (DEBUG) print *, 'Done Calc_turb_fluxes_my...'

    end subroutine Calc_turb_fluxes_my


    subroutine Fill_q_sq_with_q_sq_prog (q_sq_prog, q_sq, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq_prog
      real, dimension (kms:kme), intent (in)                    :: dn, dnw, fnm, fnp
      real,                                        intent (in)  :: cf1, cf2, cf3
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq

        ! Local vars
      integer :: i, j, k
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end
      real    :: cft1, cft2

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Interpolate from half levels to full levels
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            q_sq(i, k, j) = Max (Q_SQ_MIN, fnm(k) * q_sq_prog(i, k, j) + fnp(k) * q_sq_prog(i, k - 1, j))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Surface
          q_sq(i, kts, j) = Max (Q_SQ_MIN, q_sq(i, kts, j))
            ! Top face
          q_sq(i, ktf + 1, j) = Q_SQ_MIN
        end do
      end do

    end subroutine Fill_q_sq_with_q_sq_prog


    subroutine Fill_q_sq_prog_with_q_sq (q_sq_prog, q_sq, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_prog

        ! Local vars
      integer :: i, j, k
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end
      real    :: cft1, cft2

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Interpolate from half levels to full levels
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_prog(i, k, j) = 0.5 * ( q_sq(i, k + 1, j) + q_sq(i, k, j) )
          end do
        end do
      end do

    end subroutine Fill_q_sq_prog_with_q_sq


    subroutine Calc_l_master_algebra (pbl3d_l_opt, pbl3d_l0_opt, q_sq, dz, rdzw, rmol, wthv, dthetav_dz, l_master, &
              l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                             !
        ! Purpose: Calculates the master length scale following MY74  !
        !          Also included MYNN length scale formulation        !
        !                                                             !
        ! Author: Pedro A. Jimenez & Timothy W. Juliano               !
        !                                                             !
        ! Comments: Use an algebraic equation to calculate L          !
        !                                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer,                                     intent (in) :: pbl3d_l_opt, pbl3d_l0_opt
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: dz, rdzw
      real, dimension (ims:ime, jms:jme),          intent (in) :: rmol
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: wthv
      real, dimension (its:ite, kts:kte, jts:jte), intent (in) :: dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: l_master, l_boulac
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte

        ! Local vars
      real, dimension (kts:kte) :: z_at_walls_1d
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real, parameter :: SMALL_VAL = 0.00001
!      real, parameter :: alpha_1 = 0.23
        ! Original MYNN vals
!      real, parameter :: alpha_2 = 1.0
!      real, parameter :: alpha_3 = 5.0
!      real, parameter :: alpha_4 = 100.0
!      real, parameter :: cns = 2.7
        ! Operational MYNN vals
!      real, parameter :: alpha_2 = 0.65
!      real, parameter :: alpha_3 = 3.0
!      real, parameter :: alpha_4 = 20.0
!      real, parameter :: cns = 2.3
        ! Experimental MYNN vals
!      real, parameter :: alpha_2 = 0.3
!      real, parameter :: alpha_3 = 2.0
!      real, parameter :: alpha_4 = 10.0
!      real, parameter :: cns = 3.5
        ! 3DTKE MYNN vals
      real, parameter :: alpha_1 = 0.8
      real, parameter :: alpha_2 = 1.0
      real, parameter :: alpha_3 = 1.0
      real, parameter :: alpha_4 = 100.0
      real, parameter :: cns = 2.7
      real :: l0, l0_num, l0_den, qdz
      real :: q, q_dz, dz_wall, q_min
      real :: l_s, l_b, l_f, zet, kz, N, q_c

      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      q_min = Sqrt (Q_SQ_MIN)

         ! Calculates l0 (Eq. 72 MY74)
         !
         ! l0 is the q-weighted mean height of the turbulence, integrated over the whole
         ! column. MY74's integral converges because q -> 0 above the turbulent layer, but
         ! q_sq here is floored at Q_SQ_MIN, so with pbl3d_l0_opt = 0 every quiescent level
         ! contributes q_min = Sqrt (Q_SQ_MIN) rather than nothing. The numerator then grows
         ! like H^2 while the denominator grows like H, so l0 -> alpha * H / 2: the boundary
         ! layer length scale ends up set by where the model lid is, not by the turbulence.
         ! For a 20 km top and alpha = 0.1 that is l0 = 800 m in a nocturnal boundary layer
         ! whose turbulence supports about 3.5 m, and it drives N * tau past the point where
         ! the 10x10 system stops being solvable inside cold pools.
         !
         ! pbl3d_l0_opt = 1 weights by the turbulent excess Max (q - q_min, 0) instead, which
         ! restores the intended meaning: Q_SQ_MIN is a device to keep q_sq positive, not a
         ! physical turbulence level to be integrated. MYNN applies the same correction (see
         ! module_bl_mynnedmf.F, "originally integrated to model top, not just pblh"), there
         ! by truncating at the PBL top and subtracting qmin from the weight. Truncating is
         ! avoided here on purpose: it needs pblh, which is ill posed over complex terrain and
         ! would cut off elevated turbulent layers such as a cold pool top or a foehn shear
         ! layer. The excess weighting is local and needs no PBL depth at all.
      do j = j_start, j_end
        do i = i_start, i_end
          l0_num = SMALL_VAL
          l0_den = SMALL_VAL
          z_at_walls_1d(kts) = 0.0
          do k = kts + 1, ktf
            z_at_walls_1d(k) = z_at_walls_1d(k - 1) + 1.0 / rdzw(i, k - 1, j)
            dz_wall = 0.5 * (dz(i, k, j) + dz(i, k - 1, j))
            if (pbl3d_l0_opt == 1) then
              q = Max (Sqrt (q_sq(i, k, j)) - q_min, 0.0)
            else
              q = Sqrt (q_sq(i, k, j))
            end if
            q_dz = q * dz_wall
            l0_num = l0_num + q_dz * z_at_walls_1d(k)
            l0_den = l0_den + q_dz
          end do
          z_at_walls_1d(ktf + 1) = z_at_walls_1d(ktf) + 1.0 / rdzw(i, ktf, j)

          if (pbl3d_l_opt == 1) then  ! MY alpha
            l0 = alpha * l0_num / l0_den
          else if (pbl3d_l_opt == 2) then  ! MYNN alpha
            l0 = alpha_1 * l0_num / l0_den
            q_c = (G_OVER_TREF * Max (wthv(i, kts, j), 0.0) * l0) ** ( 1.0 / 3.0 )
          end if

          do k = kts, ktf
            if (pbl3d_l_opt == 1) then
               ! Calculates master length scale (Eq. 71 MY74)
              l_master(i, k, j) = l0 * KARMAN * z_at_walls_1d(k) / (KARMAN * z_at_walls_1d(k) + l0)
               ! Buoyancy limit l <= N_TAU_MAX q / N (Deardorff 1980; see the N_TAU_MAX block at
               ! the top of this module). Eq. 71 is purely geometric: it knows the distance to
               ! the ground and the depth of the turbulent layer, but not whether there is any
               ! turbulence at this level. Where q has collapsed and l has not, tau = l / q and
               ! hence N tau become unbounded, and the algebraic closure is solved far outside
               ! its validity range. q_sq is used as stored, i.e. floored at Q_SQ_MIN rather
               ! than reduced by q_min as in the l0 integral above, so that l stays strictly
               ! positive: l appears as 1 / tau = q / l in A and as a divisor in the
               ! dissipation, and must not be driven to zero.
              if (dthetav_dz(i, k, j) > 0.0) then
                N = Sqrt (G_OVER_TREF * dthetav_dz(i, k, j))
                l_master(i, k, j) = Min (l_master(i, k, j),                                  &
                                         N_TAU_MAX * Sqrt (q_sq(i, k, j)) / N)
              end if
               ! l_boulac is intent(out) and is read again below and by
               ! Fill_dissip_length_scale, so it must be defined on every branch. MY74 makes no
               ! distinction between the mixing and the dissipation length scale, so they are
               ! the same field here.
              l_boulac(i, k, j) = l_master(i, k, j)
            else if (pbl3d_l_opt == 2) then
               ! Calculates master length scale (Nakanishi 2001)
               ! l surface
              kz  = KARMAN * z_at_walls_1d(k)
              zet = rmol(i, j) * z_at_walls_1d(k)
              if (zet > 0.0) then
                l_s = kz / (1.0 + cns * MIN(1.0, zet))
              else
                l_s = kz * (1.0 - alpha_4 * zet) ** 0.2
              end if
               ! l buoyancy
              if (dthetav_dz(i, k, j) > 0.0) then
                N = Sqrt (G_OVER_TREF * dthetav_dz(i, k, j))
                 ! note q_c is a velocity scale defined on the ground hence kts index
                l_b = alpha_2 * Sqrt (q_sq(i, k, j)) / N * ( 1.0 + alpha_3 / alpha_2 * Sqrt (q_c / (l0 * N)) )
                l_f = alpha_2 * Sqrt (q_sq(i, k, j)) / N
              else
                l_b = 1.0E10
                l_f = l_b
              end if

              l_master(i, k, j) = MIN( (l_s * l0 * l_b) / (l_s * l0 + l_s * l_b + l0 * l_b), l_f )
              l_boulac(i, k, j) = l_master(i, k, j)  ! here we are just filling in dissipation boulac length scale

            end if
          end do
          l_master(i, kte, j) = l_master(i, ktf, j)
          l_boulac(i, kte, j) = l_boulac(i, ktf, j)

          if (DEBUG) call Debug_l_master_algebra

        end do
      end do

      contains

        subroutine Debug_l_master_algebra

          if (i == I_TO_TEST .and. j == J_TO_TEST) then
              print *, 'l_master = '
              print *, l_master(I_TO_TEST, :, J_TO_TEST)
              print *, 'l0 =', l0
              print *, 'l0_num =', l0_num
              print *, 'l0_den =', l0_den
              print *, 'z_at_walls = '
              print *, z_at_walls_1d
              print *, 'dz = '
              print *, dz(i, :, j)
              print *, 'rdzw = '
              print *, rdzw(i, :, j)
              print *, 'dzw = '
              print *, 1.0 / rdzw(i, :, j)
            end if

        end subroutine Debug_l_master_algebra

    end subroutine Calc_l_master_algebra


    subroutine Calc_l_messinger_master_algebra (pbl3d_l0_opt, q_sq, dz, rdzw, rmol, wthv, dthetav_dz, l_master, &
              l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                             !
        ! Purpose: Calculates the master length scale following MY74  !
        !          Also included MYNN length scale formulation        !
        !                                                             !
        ! Author: Pedro A. Jimenez & Timothy W. Juliano               !
        !                                                             !
        ! Comments: Use an algebraic equation to calculate L          !
        !                                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer,                                     intent (in) :: pbl3d_l0_opt
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: dz, rdzw
      real, dimension (ims:ime, jms:jme),          intent (in) :: rmol
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: wthv
      real, dimension (its:ite, kts:kte, jts:jte), intent (in) :: dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: l_master, l_boulac
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte

        ! Local vars
      real, dimension (kts:kte) :: z_at_walls_1d
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real, parameter :: SMALL_VAL = 0.00001
      real, parameter :: alpha_1 = 0.23
      real :: l0, l0_num, l0_den, qdz
      real :: q, q_dz, dz_wall, q_min
      real :: l_b, l_d, l_del, N, zi
      real, parameter :: c_r = 0.25
      real, parameter :: c_g = 10.
      real, parameter :: c_s = 0.23

      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      q_min = Sqrt (Q_SQ_MIN)

         ! Calculates l0 (Eq. 72 MY74). See Calc_l_master_algebra for why pbl3d_l0_opt = 1
         ! weights the integral by the turbulent excess over the Q_SQ_MIN floor.
      do j = j_start, j_end
        do i = i_start, i_end
          l0_num = SMALL_VAL
          l0_den = SMALL_VAL
          z_at_walls_1d(kts) = 0.0
          do k = kts + 1, ktf
            z_at_walls_1d(k) = z_at_walls_1d(k - 1) + 1.0 / rdzw(i, k - 1, j)
            dz_wall = 0.5 * (dz(i, k, j) + dz(i, k - 1, j))
            if (pbl3d_l0_opt == 1) then
              q = Max (Sqrt (q_sq(i, k, j)) - q_min, 0.0)
            else
              q = Sqrt (q_sq(i, k, j))
            end if
            q_dz = q * dz_wall
            l0_num = l0_num + q_dz * z_at_walls_1d(k)
            l0_den = l0_den + q_dz
          end do
          z_at_walls_1d(ktf + 1) = z_at_walls_1d(ktf) + 1.0 / rdzw(i, ktf, j)

          l0 = alpha * l0_num / l0_den

          zi = c_g * l0

          do k = kts + 1, ktf
              ! Unstable and neutral layers have no buoyancy limit. Without this guard
              ! Sqrt of a negative argument gives a NaN N, l_d is NaN, and whether the
              ! Min below propagates it is processor dependent.
            if (dthetav_dz(i, k, j) > 0.0) then
              N = Sqrt (G_OVER_TREF * dthetav_dz(i, k, j))
              l_d = c_r * Sqrt (q_sq(i, k, j)) / N
            else
              l_d = 1.0E10
            end if

            l_b = l0 * KARMAN * z_at_walls_1d(k) / (KARMAN * z_at_walls_1d(k) + l0)

            if (z_at_walls_1d(k) <= zi) then
              l_master(i, k, j) = Min (l_b, l_d)
            else
              l_del = c_s * (1.0 / rdzw(i, k, j))
              l_master(i, k, j) = Min (l_del, l_d, KARMAN * z_at_walls_1d(k))
            end if
            l_boulac(i, k, j) = l_master(i, k, j)  ! here we are just filling in dissipation boulac length scale
          end do

          l_master(i, kts, j) = 0.0
          l_boulac(i, kts, j) = 0.0
          l_master(i, kte, j) = l_master(i, ktf, j)
          l_boulac(i, kte, j) = l_boulac(i, ktf, j)

        end do
      end do

    end subroutine Calc_l_messinger_master_algebra


    subroutine Calc_l_boulac_master_algebra (q_sq, dz, th, dlu, dld, dls, dlk, l_master, l_boulac, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                             !
        ! Purpose: Calculates the master length scale following       !
        !          Bougeault and Lacarrere (1989) and                 ! 
        !          Martilli et al. (2002)                             !
        !                                                             !
        ! Author: Timothy W. Juliano                                  !
        !                                                             !
        ! Comments: Adapted from Boulac PBL scheme code               !
        !                                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: th
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dlu, dld, dls, dlk
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: l_master, l_boulac
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte

        ! Local vars
      integer :: i, j, k, kk, i_start, i_end, j_start, j_end, ktf
      real :: beta, bbb, zup, zdo, zdo_sup, zzz, zup_inf, dzt, te, tl
      real, dimension (its:ite, kts:kte, jts:jte) :: z

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Calculate height agl
      do j = j_start, j_end
        do i = i_start, i_end
          z(i, kts, j) = 0.0
          do k = kts + 1, kte
            z(i, k, j) = z(i, k - 1, j) + dz(i, k - 1, j)
          end do
        end do
      end do

        ! Calculate up and down length scales according to BouLac
      do j = j_start, j_end
        do i = i_start, i_end
          do k = kts, kte
            zup = 0.
            dlu(i, k, j) = z(i, kte, j) - z(i, k, j) - dz(i, k, j)/2.
            zzz = 0.
            zup_inf = 0.
            beta = G_OVER_TREF      !Buoyancy coefficient
            te = Max (q_sq(i, k, j) / 2., Q_SQ_MIN)
            do kk = k, kte - 1
              dzt = (dz(i, kk + 1, j) + dz(i, kk, j)) / 2.
              zup = zup - beta * th(i, k, j) * dzt
              zup = zup + beta * (th(i, kk + 1, j) + th(i, kk, j)) * dzt / 2.
              zzz = zzz + dzt
              if (te .lt. zup .and. te .ge. zup_inf) then
                bbb = (th(i, kk + 1, j) - th(i, kk, j)) / dzt
                if (bbb .ne. 0) then
                  tl = (-beta * (th(i, kk, j) - th(i, k, j)) + sqrt( max( 0.0, (beta * (th(i, kk, j) - th(i, k, j)))**2. + &
                            2. * bbb * beta * (te - zup_inf)))) / bbb / beta
                else
                  if (th(i, kk, j) .ne. th(i, k, j)) then
                    tl = (te - zup_inf) / (beta * (th(i, kk, j) - th(i, k, j)))
                  else
                    tl = 0.
                  end if
                end if
                dlu(i, k, j) = zzz - dzt + tl
              end if
              zup_inf = zup
            end do

            zdo = 0.
            zdo_sup = 0.
            dld(i, k, j) = z(i, k, j) + dz(i, k, j) / 2.
            zzz = 0.
            do kk = k, kts + 1, -1
              dzt = (dz(i, kk - 1, j) + dz(i, kk, j)) / 2.
              zdo = zdo + beta * th(i, k, j) * dzt
              zdo = zdo - beta * (th(i, kk - 1, j) + th(i, kk, j)) * dzt / 2.
              zzz = zzz + dzt
              if (te .lt. zdo .and. te .ge. zdo_sup) then
                bbb = (th(i, kk, j) - th(i, kk - 1, j)) / dzt
                if (bbb .ne. 0.0) then
                  tl = (beta * (th(i, kk, j) - th(i, k, j)) + sqrt( max( 0.0, (beta * (th(i, kk, j) - th(i, k, j)))**2. + &
                           2. * bbb * beta * (te - zdo_sup)))) / bbb / beta
                else
                  if (th(i, kk, j) .ne. th(i, k, j)) then
                    tl = (te - zdo_sup) / (beta * (th(i, kk, j) - th(i, k, j)))
                  else
                    tl = 0.
                  end if
                end if
                dld(i, k, j) = zzz - dzt + tl
              end if
              zdo_sup = zdo
            end do
          end do

            ! Compute turbulent and dissipation length scales
          do k = kts, ktf
            dlu(i, k, j) = max( dlu(i, k, j), 0.0 )
            dld(i, k, j) = max( min( dld(i, k, j), z(i, k, j) ), 0.0 )
            dls(i, k, j) = max( sqrt( dlu(i, k, j) * dld(i, k, j) ), 0.1 )
            dlk(i, k, j) = min( dlu(i, k, j), dld(i, k, j) )
            l_master(i, k, j) = dlk(i, k, j)  ! turbulent length scale
            l_boulac(i, k, j) = dls(i, k, j)  ! dissipation length scale
          end do
          l_master(i, kte, j) = l_master(i, ktf, j)
          l_boulac(i, kte, j) = l_boulac(i, ktf, j)
        end do
      end do

    end subroutine Calc_l_boulac_master_algebra


    subroutine Calc_fluxes_pbl_approx (config_flags, ss, Psig_bl, l_master, l_boulac, du_dz, dv_dz, dthetav_dz, dqv_dz, &
              dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz, &
              t, qv, dn, dnw, fnm, fnp, dx, dy, dz, z_at_w, zx, zy, msftx, msfty, rdz, rdzw, cf1, cf2, cf3, dt, id, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts,    &
              jte, kts, kte, q_sq, q_sq_prog, turb_flux_u2, turb_flux_v2, turb_flux_w2,     &
              turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                 &
              turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_uqv,    &
              turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, &
              turb_flux_uqc, turb_flux_vqc, turb_flux_wqc, turb_flux_uqr, turb_flux_vqr, turb_flux_wqr, &
              turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, turb_flux_uqs, turb_flux_vqs, turb_flux_wqs, &
              turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, turb_flux_uqnc, turb_flux_vqnc, turb_flux_wqnc, &
              turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_wqni, &
              turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa, &
              u, v, w, thetav, rho, ust, hfx, qfx, rmol)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                   !
      ! Purpose: Diagnose q_sq and turb fluxes                            !
      !                                                                   !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                     !
      !                                                                   !
      ! Comments: q_sq and fluxes are calculated at the faces             !
      !                                                                   !
      ! References: Y75                                                   !
      !                                                                   !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags
      integer,                                     intent (in)    :: ss

      real, dimension (kms:kme),                   intent (in)    :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)    :: Psig_bl
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: dz, zx, zy, rdz, rdzw, z_at_w
      real,                                        intent (in)    :: cf1, cf2, cf3, dt, dx, dy
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz, dqv_dz, &
          dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: l_master, l_boulac
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: turb_flux_u2, &
          turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw,        &
          turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v,                  &
          turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv,             &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,                        &
          turb_flux_uqc, turb_flux_vqc, turb_flux_wqc,                                 &
          turb_flux_uqr, turb_flux_vqr, turb_flux_wqr,                                 &
          turb_flux_uqi, turb_flux_vqi, turb_flux_wqi,                                 &
          turb_flux_uqs, turb_flux_vqs, turb_flux_wqs,                                 &
          turb_flux_uqg, turb_flux_vqg, turb_flux_wqg,                                 &
          turb_flux_uqnc, turb_flux_vqnc, turb_flux_wqnc,                              &
          turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr,                              &
          turb_flux_uqni, turb_flux_vqni, turb_flux_wqni,                              &
          turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa,                        &
          turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u, v, w, t, thetav, rho, qv
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx, msfty, ust, hfx, qfx, rmol
      integer, intent (in)    :: id
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: rif, sm_l2, sh_l2, sm, sh, q_ratio, q_sq_hl88
      real, dimension (its:ite, kts:kte, jts:jte) :: dlu, dld, dls, dlk
      integer :: i, j

        ! Calculate q_sq (level 2) or Fill q_sq with prognostic q_sq (level 2.5)
      if ( config_flags%pbl3d_prog .eq. 0 ) then   ! level 2 model
        call Prep_for_fluxes_l2_pbl_approx (config_flags, q_sq, l_master, l_boulac, rif, sm, sh, du_dz, dv_dz, &
            dthetav_dz, id, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      else if ( config_flags%pbl3d_prog .gt. 0 ) then   ! level 2.5 model
        call Prep_for_fluxes_l2p5_pbl_approx (config_flags, q_sq, q_sq_prog, l_master, l_boulac, rif, sm_l2, sh_l2, sm, sh, &
            q_ratio, q_sq_hl88, du_dz, dv_dz, dthetav_dz, id, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
            ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

        ! Diagnose master length scale at faces
      if (config_flags%pbl3d_l_opt < 3) then
        call Calc_l_master_algebra (config_flags%pbl3d_l_opt, config_flags%pbl3d_l0_opt, q_sq, dz, rdzw, rmol, turb_flux_wtheta_v, dthetav_dz, l_master, &
            l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      else if (config_flags%pbl3d_l_opt == 3) then
        call Calc_l_boulac_master_algebra (q_sq, dz, t, dlu, dld, dls, dlk, l_master, l_boulac, &
            ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      else
        call Calc_l_messinger_master_algebra (config_flags%pbl3d_l0_opt, q_sq, dz, rdzw, rmol, turb_flux_wtheta_v, dthetav_dz, l_master, &
            l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

        ! Apply scale-aware tapering
      call Make_scale_aware (Psig_bl, l_master, l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Diagnose momentum, heat, moisture fluxes for pbl approx
      if ( config_flags%pbl3d_prog .eq. 0 ) then  ! For level 2 model, no need for realizability
        call Diagnose_fluxes_pbl_approx (do_scalar_mix=config_flags%pbl3d_scalar_mix, ss=ss, nsteps=config_flags%pbl3d_nsteps, &
            fnm=fnm, fnp=fnp, t=t, qv=qv, ust=ust, hfx=hfx, qfx=qfx, sm_tilde=sm, sh_tilde=sh, rif=rif, &
            q_sq=q_sq, l_master=l_master, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, dqv_dz=dqv_dz, &
            dqc_dz=dqc_dz, dqr_dz=dqr_dz, dqi_dz=dqi_dz, dqs_dz=dqs_dz, dqg_dz=dqg_dz, dqnc_dz=dqnc_dz, &
            dqnr_dz=dqnr_dz, dqni_dz=dqni_dz, dqnwfa_dz=dqnwfa_dz, dqnifa_dz=dqnifa_dz, u2=turb_flux_u2, &
            v2=turb_flux_v2, w2=turb_flux_w2, uv=turb_flux_uv, uw=turb_flux_uw, vw=turb_flux_vw, uthv=turb_flux_utheta_v, vthv=turb_flux_vtheta_v, &
            wthv=turb_flux_wtheta_v, th2v=turb_flux_theta2_v, uqv=turb_flux_uqv, vqv=turb_flux_vqv, wqv=turb_flux_wqv, &
            uqc=turb_flux_uqc, vqc=turb_flux_vqc, wqc=turb_flux_wqc, uqr=turb_flux_uqr, vqr=turb_flux_vqr, wqr=turb_flux_wqr, &
            uqi=turb_flux_uqi, vqi=turb_flux_vqi, wqi=turb_flux_wqi, uqs=turb_flux_uqs, vqs=turb_flux_vqs, wqs=turb_flux_wqs, &
            uqg=turb_flux_uqg, vqg=turb_flux_vqg, wqg=turb_flux_wqg, uqnc=turb_flux_uqnc, vqnc=turb_flux_vqnc, &
            wqnc=turb_flux_wqnc, uqnr=turb_flux_uqnr, vqnr=turb_flux_vqnr, wqnr=turb_flux_wqnr, uqni=turb_flux_uqni, &
            vqni=turb_flux_vqni, wqni=turb_flux_wqni, uqnwfa=turb_flux_uqnwfa, vqnwfa=turb_flux_vqnwfa, wqnwfa=turb_flux_wqnwfa, &
            uqnifa=turb_flux_uqnifa, vqnifa=turb_flux_vqnifa, wqnifa=turb_flux_wqnifa, uth=turb_flux_utheta, &
            vth=turb_flux_vtheta, wth=turb_flux_wtheta, ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, &
            ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte)
      else if ( config_flags%pbl3d_prog .gt. 0 ) then  ! For level 2.5 model, include information for HL88 mod
        call Diagnose_fluxes_pbl_approx (do_scalar_mix=config_flags%pbl3d_scalar_mix, ss=ss, nsteps=config_flags%pbl3d_nsteps, &
            fnm=fnm, fnp=fnp, t=t, qv=qv, ust=ust, hfx=hfx, qfx=qfx, sm_tilde=sm, sh_tilde=sh, sm_l2=sm_l2, sh_l2=sh_l2, rif=rif, &
            q_sq=q_sq, q_sq_hl88=q_sq_hl88, q_ratio=q_ratio, l_master=l_master, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, dqv_dz=dqv_dz, &
            dqc_dz=dqc_dz, dqr_dz=dqr_dz, dqi_dz=dqi_dz, dqs_dz=dqs_dz, dqg_dz=dqg_dz, dqnc_dz=dqnc_dz, &
            dqnr_dz=dqnr_dz, dqni_dz=dqni_dz, dqnwfa_dz=dqnwfa_dz, dqnifa_dz=dqnifa_dz, u2=turb_flux_u2, &
            v2=turb_flux_v2, w2=turb_flux_w2, uv=turb_flux_uv, uw=turb_flux_uw, vw=turb_flux_vw, uthv=turb_flux_utheta_v, vthv=turb_flux_vtheta_v, &
            wthv=turb_flux_wtheta_v, th2v=turb_flux_theta2_v, uqv=turb_flux_uqv, vqv=turb_flux_vqv, wqv=turb_flux_wqv, &
            uqc=turb_flux_uqc, vqc=turb_flux_vqc, wqc=turb_flux_wqc, uqr=turb_flux_uqr, vqr=turb_flux_vqr, wqr=turb_flux_wqr, &
            uqi=turb_flux_uqi, vqi=turb_flux_vqi, wqi=turb_flux_wqi, uqs=turb_flux_uqs, vqs=turb_flux_vqs, wqs=turb_flux_wqs, &
            uqg=turb_flux_uqg, vqg=turb_flux_vqg, wqg=turb_flux_wqg, uqnc=turb_flux_uqnc, vqnc=turb_flux_vqnc, &
            wqnc=turb_flux_wqnc, uqnr=turb_flux_uqnr, vqnr=turb_flux_vqnr, wqnr=turb_flux_wqnr, uqni=turb_flux_uqni, &
            vqni=turb_flux_vqni, wqni=turb_flux_wqni, uqnwfa=turb_flux_uqnwfa, vqnwfa=turb_flux_vqnwfa, wqnwfa=turb_flux_wqnwfa, &
            uqnifa=turb_flux_uqnifa, vqnifa=turb_flux_vqnifa, wqnifa=turb_flux_wqnifa, uth=turb_flux_utheta, &
            vth=turb_flux_vtheta, wth=turb_flux_wtheta, ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, &
            ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte)
      end if

      call Diagnose_fluxes_surface (config_flags%pbl3d_sfc_opt, u, v, t, rho, dz, qv, ust, hfx, qfx, &
          rmol, q_sq, l_master, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
          turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, &
          turb_flux_wtheta, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

    end subroutine Calc_fluxes_pbl_approx


    subroutine Prep_for_fluxes_l2_pbl_approx (config_flags, q_sq, l_master, l_boulac, rif, sm, sh, du_dz, dv_dz, &
              dthetav_dz, id, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Calculate stability functions for q_sq diagnosis          !
      !                                                                    !
      ! Author: Timothy W. Juliano                                         !
      !                                                                    !
      ! Comments: Stability functions and q_sq are calculated at the faces !
      !           The q_sq equation is for the PBL approximation           !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags

      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out)   :: rif, sm, sh
      integer, intent (in)    :: id
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: l_dissip
      character (4) :: my_level

      my_level = 'l2'
        ! Calc stability functions for level 2 model
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
         ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
         its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm, sh=sh, rif=rif)
      call Fill_dissip_length_scale (config_flags%pbl3d_l_opt, l_master, l_boulac, l_dissip, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      call Calc_q_sq_l2_pbl_approx (l_master=l_master, l_dissip=l_dissip, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, ids=ids, ide=ide, &
          jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, &
          jts=jts, jte=jte, kts=kts, kte=kte, q_sq_face=q_sq, sm=sm, rif=rif)
        ! Relax q_sq at the boundaries (only for parent domain and specified B.C. runs)
      if ( id .eq. 1 .and. config_flags%specified) then
        call Taper_q_sq (q_sq, ids, jds, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

    end subroutine Prep_for_fluxes_l2_pbl_approx


    subroutine Prep_for_fluxes_l2p5_pbl_approx (config_flags, q_sq, q_sq_prog, l_master, l_boulac, rif, sm_l2, sh_l2, sm, sh, &
              q_ratio, q_sq_hl88, du_dz, dv_dz, dthetav_dz, id, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                           !
      ! Purpose: Calculate stability functions for q_sq diagnosis (level 2 model) !
      !          so that we can apply HL88 realizability criterion                !
      !          Also calculate stability functions for level 2.5 model           !
      !                                                                           !
      ! Author: Timothy W. Juliano                                                !
      !                                                                           !
      ! Comments: Stability functions and q_sq are calculated at the faces        !
      !           The q_sq equation is for the PBL approximation                  !
      !                                                                           !
      ! References: Helfand and Labraga (1988, JAS)                               !
      !                                                                           !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags

      real, dimension (kms:kme),                   intent (in)    :: dn, dnw, fnm, fnp
      real,                                        intent (in)    :: cf1, cf2, cf3
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out)   :: rif, sm_l2, sh_l2, sm, sh, q_ratio, q_sq_hl88
      integer, intent (in)    :: id
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: l_dissip
      character (4) :: my_level

        ! Calc sm and sh then q_sq for the level 2 model to prepare for the HL88 fix.
        !
        ! This used to sit inside "if (use_hl88)" with use_hl88 a local parameter fixed at
        ! .true. and no else branch. Flipping it would have left rif, sm_l2, sh_l2 and
        ! q_sq_hl88 undefined while still passing them to Calc_sm_sh_l2_or_l2p5 below, which
        ! reads all four. There is no defined physics for "HL88 off" - the else branch of the
        ! limiter is not the identity - so the flag is removed rather than given an invented
        ! meaning. Disabling HL88 would need a namelist option and a stated definition.
      my_level = 'l2'
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
          ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm_l2, sh=sh_l2, rif=rif)
      call Fill_dissip_length_scale (config_flags%pbl3d_l_opt, l_master, l_boulac, l_dissip, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      call Calc_q_sq_l2_pbl_approx (l_master=l_master, l_dissip=l_dissip, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, ids=ids, ide=ide, &
          jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, &
          jts=jts, jte=jte, kts=kts, kte=kte, q_sq_hl88=q_sq_hl88, sm=sm_l2, rif=rif)

      call Fill_q_sq_with_q_sq_prog (q_sq_prog, q_sq, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      my_level = 'l2p5'
        ! Calc stability functions for level 2.5 model
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, ids=ids, ide=ide, &
        jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, jts=jts, jte=jte, &
        kts=kts, kte=kte, sm_l2=sm_l2, sh_l2=sh_l2, sm=sm, sh=sh, q_sq=q_sq, q_sq_hl88=q_sq_hl88, q_ratio=q_ratio, l_master_at_face=l_master)

    end subroutine Prep_for_fluxes_l2p5_pbl_approx


    subroutine Calc_fluxes (config_flags, id, specified, q_sq, q_sq_prog, Psig_bl, l_master, l_boulac, du_dx, du_dy, du_dz, dv_dx, dv_dy,  &
        dv_dz, dw_dx, dw_dy, dw_dz, dthetav_dx, dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, &
        dqv_dz, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw,   &
        turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v,       &
        turb_flux_theta2_v, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,       &
        turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, t, thetav, qv, rho, hfx, qfx, rmol, u, v, ust, &
        pbl3d_t1_ratio, pbl3d_t2_steps, pbl3d_t3_flags, pbl3d_sk_eps, pbl3d_n_tau, pbl3d_cond_a, pbl3d_qv2,   &
        dz, rdzw, z_at_w, fnm, fnp, cf1, cf2, cf3, dn, dnw, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, &
        its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                !
      ! Purpose: Diagnoses turb fluxes                                 !
      !                                                                !
      ! Author: Pedro A. Jimenez                                       !
      !                                                                !
      ! Comments: The fluxes are calculated at the faces.              !
      !                                                                !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags

      logical,                                     intent (in)    :: specified
      integer,                                     intent (in)    :: id

      integer,                                     intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dx, dv_dy, dw_dz, du_dy, dv_dx,      &
                                                                     dw_dx, du_dz, dw_dy, dv_dz, dthetav_dx, &
                                                                     dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, &
                                                                     dqv_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: turb_flux_u2, turb_flux_v2, turb_flux_w2, &
                                                                     turb_flux_uv, turb_flux_uw, turb_flux_vw, &
                                                                     turb_flux_utheta_v, turb_flux_vtheta_v,   &
                                                                     turb_flux_wtheta_v, turb_flux_theta2_v,   &
                                                                     turb_flux_utheta, turb_flux_vtheta,       &
                                                                     turb_flux_wtheta, turb_flux_uqv,          &
                                                                     turb_flux_vqv, turb_flux_wqv,             &
                                                                     q_sq, l_master, l_boulac
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: pbl3d_t1_ratio, pbl3d_t2_steps, &
                                                                     pbl3d_t3_flags, pbl3d_sk_eps,   &
                                                                     pbl3d_n_tau, pbl3d_cond_a, pbl3d_qv2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: u, v, rho, t, thetav, qv
      real, dimension (ims:ime, jms:jme),          intent (in)    :: ust, hfx, qfx, rmol
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: dz, rdzw, z_at_w
      real, dimension (kms:kme),                   intent (in)    :: fnm, fnp, dn, dnw
      real, dimension (ims:ime, jms:jme),          intent (in)    :: Psig_bl
      real,                                        intent (in)    :: cf1, cf2, cf3

        ! Local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real, dimension (its:ite, kts:kte, jts:jte) :: sm, sh, sm_l2, sh_l2, rif, q_sq_hl88, q_ratio
      real, dimension (its:ite, kts:kte, jts:jte) :: dlu, dld, dls, dlk
      real, dimension (its:ite, kts:kte, jts:jte) :: mat_cond_heat, mat_cond_moist

      real (kind = SOLVER_PREC) :: tf_utv, tf_vtv, tf_wtv, tf_uqv, tf_vqv, tf_wqv

      integer :: n_backoff_pt, n_backoff_tot, n_pts_limited
      real    :: dg_t1_ratio, dg_t3_flags, dg_sk_eps, dg_n_tau, dg_qv2
        ! Summary counters, binned by stratification so the report says under WHICH
        ! conditions each tier fired, not only how often.
      integer :: n_pts_tot, n_t1, n_t2, n_t2_max, n_t3(8)
      integer :: n_bin(3), n_t2_bin(3), n_t3_bin(3)
      integer :: ib, ibit
      real    :: sk_max, ntau_min, ntau_max, cond_max_seen

      character (4) :: my_level
      character (len = 256) :: wrf_err_message

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Calculate q_sq (level 2) or Fill q_sq with prognostic q_sq (level 2.5).
        !
        ! pbl3d_qsq_opt = 1 closes q^2 on the full 3D production evaluated with the stress
        ! tensor this routine itself produced on the previous step, so the velocity scale
        ! that sets the relaxation time q / (2 a_1 l) on the diagonal of A comes from the
        ! same turbulence A describes. pbl3d_qsq_opt = 0 restores the legacy path, which
        ! closes q^2 on du/dz and dv/dz alone and therefore hands the 3D system a time
        ! scale derived from a model that cannot see the anisotropy the system exists to
        ! represent. The legacy path is kept for testing and for bisecting against runs
        ! made before the self consistent path was repaired.
        !
        ! Note that for pbl3d_prog > 0 the two differ only in q_sq_hl88, which feeds the
        ! HL88 limiter on sm and sh, and sm and sh are not read anywhere on the full 3D
        ! path. The switch is therefore only consequential for pbl3d_prog = 0.
        !
        ! sm, sh, sm_l2, sh_l2 and q_ratio are returned by the calls below and then
        ! deliberately not used. This is not an oversight and they must not be wired in:
        ! stability functions are how the *approximate* closure forms its fluxes, whereas
        ! this path forms them by solving the 10x10 system, so there is no place for an Sm or
        ! an Sh in it. HL88 is the level 2.5 realizability limiter for the stability function
        ! formulation; its full 3D counterpart is Enforce_realizability, which is applied in
        ! Diagnose_fluxes. The wasted work is one 3D sweep of a few tens of flops per point
        ! against two dense linear solves per point, so it is well under one percent of the
        ! scheme and is left in place rather than special cased, because the same prep
        ! routines are shared with Calc_fluxes_pbl_approx where sm and sh are live.
      if ( config_flags%pbl3d_qsq_opt .eq. 1 ) then

        if ( config_flags%pbl3d_prog .eq. 0 ) then   ! level 2 model
          call Prep_for_fluxes_l2 (config_flags, q_sq, l_master, l_boulac, rif, sm, sh, du_dx, dv_dy, dw_dz, &
              du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz, turb_flux_u2, turb_flux_v2, turb_flux_w2, &
              turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, id, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        else if ( config_flags%pbl3d_prog .gt. 0 ) then   ! level 2.5 model
          call Prep_for_fluxes_l2p5 (config_flags, q_sq, q_sq_prog, l_master, l_boulac, rif, sm_l2, sh_l2, sm, sh, &
              q_ratio, q_sq_hl88, du_dx, dv_dy, dw_dz, du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz, &
              turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, &
              id, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        end if

      else

        if ( config_flags%pbl3d_prog .eq. 0 ) then   ! level 2 model
          call Prep_for_fluxes_l2_pbl_approx (config_flags, q_sq, l_master, l_boulac, rif, sm, sh, du_dz, dv_dz, &
              dthetav_dz, id, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        else if ( config_flags%pbl3d_prog .gt. 0 ) then   ! level 2.5 model
          call Prep_for_fluxes_l2p5_pbl_approx (config_flags, q_sq, q_sq_prog, l_master, l_boulac, rif, sm_l2, sh_l2, sm, sh, &
              q_ratio, q_sq_hl88, du_dz, dv_dz, dthetav_dz, id, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        end if

      end if

        ! Diagnose master length scale at faces
      if (config_flags%pbl3d_l_opt < 3) then
        call Calc_l_master_algebra (config_flags%pbl3d_l_opt, config_flags%pbl3d_l0_opt, q_sq, dz, rdzw, rmol, turb_flux_wtheta_v, dthetav_dz, l_master, &
            l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      else if (config_flags%pbl3d_l_opt == 3) then
        call Calc_l_boulac_master_algebra (q_sq, dz, t, dlu, dld, dls, dlk, l_master, l_boulac, &
            ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      else
        call Calc_l_messinger_master_algebra (config_flags%pbl3d_l0_opt, q_sq, dz, rdzw, rmol, turb_flux_wtheta_v, dthetav_dz, l_master, &
            l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

        ! Apply scale-aware tapering
      call Make_scale_aware (Psig_bl, l_master, l_boulac, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      mat_cond_heat(its:ite,kts:kte,jts:jte) = -9999.
      mat_cond_moist(its:ite,kts:kte,jts:jte) = -9999.

      n_backoff_pt  = 0
      n_backoff_tot = 0
      n_pts_limited = 0

      n_pts_tot = 0 ; n_t1 = 0 ; n_t2 = 0 ; n_t2_max = 0
      n_t3(:) = 0 ; n_bin(:) = 0 ; n_t2_bin(:) = 0 ; n_t3_bin(:) = 0
      sk_max = 0.0 ; ntau_min = 0.0 ; ntau_max = 0.0 ; cond_max_seen = 0.0

      pbl3d_t1_ratio(its:ite, kts:kte, jts:jte) = 1.0
      pbl3d_t2_steps(its:ite, kts:kte, jts:jte) = 0.0
      pbl3d_t3_flags(its:ite, kts:kte, jts:jte) = 0.0
      pbl3d_sk_eps  (its:ite, kts:kte, jts:jte) = 0.0
      pbl3d_n_tau   (its:ite, kts:kte, jts:jte) = 0.0
      pbl3d_cond_a  (its:ite, kts:kte, jts:jte) = 0.0
      pbl3d_qv2     (its:ite, kts:kte, jts:jte) = 0.0

      loop_j: do j = j_start, j_end
        loop_k: do k = kts + 1, ktf
          loop_i: do i = i_start, i_end

              ! Inequality rather than exact float equality. Calc_q_sq_l2* only ever reaches
              ! the floor through Max (..., Q_SQ_MIN) so the two agree today, but an exact
              ! comparison would silently stop firing after any refactor that reaches the
              ! floor by another route, and the scheme would then solve the 10x10 system in
              ! laminar air at q^2 = 1e-5.
            if_no_turb: if (q_sq(i, k, j) <= Q_SQ_MIN) then

              call Set_fluxes_to_min (q_sq(i, k, j), turb_flux_u2(i, k, j),   &
                 turb_flux_v2(i, k, j), turb_flux_w2(i, k, j), turb_flux_uv(i, k, j), &
                 turb_flux_uw(i, k, j), turb_flux_vw(i, k, j), turb_flux_utheta_v(i, k, j), &
                 turb_flux_vtheta_v(i, k, j), turb_flux_wtheta_v(i, k, j), turb_flux_theta2_v(i, k, j), &
                 turb_flux_utheta(i, k, j), turb_flux_vtheta(i, k, j), turb_flux_wtheta(i, k, j),  &
                 turb_flux_uqv(i, k, j), turb_flux_vqv(i, k, j), turb_flux_wqv(i, k, j) )

            else

              call Diagnose_fluxes (q_sq(i, k, j), l_master(i, k, j), du_dx(i, k, j), du_dy(i, k, j),                                &
                  du_dz(i, k, j), dv_dx(i, k, j), dv_dy(i, k, j), dv_dz(i, k, j), dw_dx(i, k, j), dw_dy(i, k, j), dw_dz(i, k, j),    &
                  dthetav_dx(i, k, j), dthetav_dy(i, k, j), dthetav_dz(i, k, j), dqv_dx(i, k, j), dqv_dy(i, k, j), dqv_dz(i, k, j),  &
                  turb_flux_u2(i, k, j), turb_flux_v2(i, k, j), turb_flux_w2(i, k, j), turb_flux_uv(i, k, j), turb_flux_uw(i, k, j), &
                  turb_flux_vw(i, k, j), turb_flux_utheta_v(i, k, j), turb_flux_vtheta_v(i, k, j), turb_flux_wtheta_v(i, k, j),      &
                  turb_flux_theta2_v(i, k, j), turb_flux_uqv(i, k, j), turb_flux_vqv(i, k, j), turb_flux_wqv(i, k, j), tf_utv,       &
                  tf_vtv, tf_wtv, tf_uqv, tf_vqv, tf_wqv, mat_cond_heat(i, k, j), mat_cond_moist(i, k, j), n_backoff_pt,       &
                  dg_t1_ratio, dg_t3_flags, dg_sk_eps, dg_n_tau, dg_qv2                                                        )

              if (n_backoff_pt > 0) then
                n_backoff_tot = n_backoff_tot + n_backoff_pt
                n_pts_limited = n_pts_limited + 1
              end if

                ! Per-point diagnostic fields, written to history
              pbl3d_t1_ratio(i, k, j) = dg_t1_ratio
              pbl3d_t2_steps(i, k, j) = Real (n_backoff_pt)
              pbl3d_t3_flags(i, k, j) = dg_t3_flags
              pbl3d_sk_eps  (i, k, j) = dg_sk_eps
              pbl3d_n_tau   (i, k, j) = dg_n_tau
              pbl3d_cond_a  (i, k, j) = mat_cond_heat(i, k, j)
              pbl3d_qv2     (i, k, j) = dg_qv2

                ! Summary bin: 1 unstable, 2 near neutral, 3 stable
              if (dg_n_tau < -0.05) then
                ib = 1
              else if (dg_n_tau > 0.05) then
                ib = 3
              else
                ib = 2
              end if
              n_pts_tot = n_pts_tot + 1
              n_bin(ib) = n_bin(ib) + 1
              if (dg_t1_ratio < 0.999999) n_t1 = n_t1 + 1
              if (n_backoff_pt > 0) then
                n_t2 = n_t2 + 1
                n_t2_bin(ib) = n_t2_bin(ib) + 1
                if (n_backoff_pt >= MAX_SOLVE_ATTEMPTS - 1) n_t2_max = n_t2_max + 1
              end if
              if (dg_t3_flags > 0.0) then
                n_t3_bin(ib) = n_t3_bin(ib) + 1
                do ibit = 1, 8
                  if (Mod (Int (dg_t3_flags) / 2 ** (ibit - 1), 2) == 1) n_t3(ibit) = n_t3(ibit) + 1
                end do
              end if
              sk_max        = Max (sk_max, dg_sk_eps)
              ntau_min      = Min (ntau_min, dg_n_tau)
              ntau_max      = Max (ntau_max, dg_n_tau)
              cond_max_seen = Max (cond_max_seen, mat_cond_heat(i, k, j))

                ! Calc heat fluxes
              call Calc_heat_flux (t, qv, fnm, fnp, i, j, k, tf_utv, tf_vtv, tf_wtv,  tf_uqv, tf_vqv, tf_wqv, &
                  turb_flux_utheta(i, k, j), turb_flux_vtheta(i, k, j), turb_flux_wtheta(i, k, j), ims, ime, jms, jme, kms, kme)

            end if if_no_turb

          end do loop_i
        end do loop_k
      end do loop_j

        ! Report how often the algebraic system had to be pushed back inside its
        ! validity range. A healthy run should show this rarely or never.
        ! How often each safeguard acted, and under which conditions. A healthy run shows
        ! Tier 1 doing most of the work, Tier 2 occasional, Tier 3 rare, and the isotropic
        ! fallback (TIER2 exhausted) never. Emitted at debug_level 100, per tile.
      if (n_pts_tot > 0) then
        write (wrf_err_message, '(A,I9,A,F6.2,A,F6.2,A,F6.2,A)')                            &
            'pbl3d diag: pts ', n_pts_tot, ' | unstable ',                                  &
            100.0 * Real (n_bin(1)) / Real (n_pts_tot), '% neutral ',                       &
            100.0 * Real (n_bin(2)) / Real (n_pts_tot), '% stable ',                        &
            100.0 * Real (n_bin(3)) / Real (n_pts_tot), '%'
        call wrf_debug (100, wrf_err_message)

        write (wrf_err_message, '(A,F8.3,A,F8.3,A,F8.3,A,E10.3)')                           &
            'pbl3d diag: max Sk/eps ', sk_max, ' | N*tau ', ntau_min, ' to ',               &
            ntau_max, ' | max cond(A) ', cond_max_seen
        call wrf_debug (100, wrf_err_message)

        write (wrf_err_message, '(A,F7.3,A,F7.3,A,I9,A,I8)')                                &
            'pbl3d diag: TIER1 bound l at ', 100.0 * Real (n_t1) / Real (n_pts_tot),        &
            '% | TIER2 escalated at ', 100.0 * Real (n_t2) / Real (n_pts_tot),              &
            '% (', n_backoff_tot, ' steps) exhausted ', n_t2_max
        call wrf_debug (100, wrf_err_message)

        write (wrf_err_message, '(A,F7.3,A,8(1X,I7))')                                      &
            'pbl3d diag: TIER3 acted at ',                                                  &
            100.0 * Real (n_t3_bin(1) + n_t3_bin(2) + n_t3_bin(3)) / Real (n_pts_tot),      &
            '% | by step [var trace CS det heat qv2 qvCS qvtvCS]:',                              &
            n_t3(1), n_t3(2), n_t3(3), n_t3(4), n_t3(5), n_t3(6), n_t3(7), n_t3(8)
        call wrf_debug (100, wrf_err_message)

        write (wrf_err_message, '(A,3(1X,I8),A,3(1X,I8))')                                  &
            'pbl3d diag: TIER2 by strat [unstab neut stab]:',                               &
            n_t2_bin(1), n_t2_bin(2), n_t2_bin(3),                                          &
            ' | TIER3:', n_t3_bin(1), n_t3_bin(2), n_t3_bin(3)
        call wrf_debug (100, wrf_err_message)
      end if

      call Diagnose_fluxes_surface (config_flags%pbl3d_sfc_opt, u, v, t, rho, dz, qv, ust, hfx, qfx, &
          rmol, q_sq, l_master, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
          turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, &
          turb_flux_wtheta, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

    end subroutine Calc_fluxes


    subroutine Prep_for_fluxes_l2 (config_flags, q_sq, l_master, l_boulac, rif, sm, sh, du_dx, dv_dy, dw_dz, &
              du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_wtv, &
              id, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Calculate stability functions for q_sq diagnosis          !
      !                                                                    !
      ! Author: Timothy W. Juliano                                         !
      !                                                                    !
      ! Comments: Stability functions and q_sq are calculated at the faces !
      !           The q_sq equation is for the full 3D model               !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags

      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dx, dv_dy, dw_dz, &
                                    du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: tf_u2, tf_v2, tf_w2, &
                                                            tf_uv, tf_uw, tf_vw, tf_wtv
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out)   :: rif, sm, sh
      integer, intent (in)    :: id
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: l_dissip
      character (4) :: my_level

      my_level = 'l2'
        ! Calc stability functions for level 2 model
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
         ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
         its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm, sh=sh, rif=rif)
      call Fill_dissip_length_scale (config_flags%pbl3d_l_opt, l_master, l_boulac, l_dissip, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      call Calc_q_sq_l2 (l_master=l_master, l_dissip=l_dissip, du_dx=du_dx, dv_dy=dv_dy, dw_dz=dw_dz, du_dy=du_dy, &
          dv_dx=dv_dx, dw_dx=dw_dx, du_dz=du_dz, dw_dy=dw_dy, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
          tf_u2=tf_u2, tf_v2=tf_v2, tf_w2=tf_w2, tf_uv=tf_uv, tf_uw=tf_uw, tf_vw=tf_vw, tf_wtv=tf_wtv, &
          ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm, q_sq_face=q_sq, rif=rif)
        ! Relax q_sq at the boundaries (only for parent domain and specified B.C. runs)
      if ( id .eq. 1 .and. config_flags%specified) then
        call Taper_q_sq (q_sq, ids, jds, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

    end subroutine Prep_for_fluxes_l2


    subroutine Prep_for_fluxes_l2p5 (config_flags, q_sq, q_sq_prog, l_master, l_boulac, rif, sm_l2, sh_l2, sm, sh, &
              q_ratio, q_sq_hl88, du_dx, dv_dy, dw_dz, du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz, &
              tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_wtv, id, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                           !
      ! Purpose: Calculate stability functions for q_sq diagnosis (level 2 model) !
      !          so that we can apply HL88 realizability criterion                !
      !          Also calculate stability functions for level 2.5 model           !
      !                                                                           !
      ! Author: Timothy W. Juliano                                                !
      !                                                                           !
      ! Comments: Stability functions and q_sq are calculated at the faces        !
      !           The q_sq equation is for the full 3D model                      !
      !                                                                           !
      ! References: Helfand and Labraga (1988, JAS)                               !
      !                                                                           !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)    :: config_flags

      real, dimension (kms:kme),                   intent (in)    :: dn, dnw, fnm, fnp
      real,                                        intent (in)    :: cf1, cf2, cf3
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dx, dv_dy, dw_dz, &
                                    du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: tf_u2, tf_v2, tf_w2, &
                                                            tf_uv, tf_uw, tf_vw, tf_wtv
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out)   :: rif, sm_l2, sh_l2, sm, sh, q_ratio, q_sq_hl88
      integer, intent (in)    :: id
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: l_dissip
      character (4) :: my_level

        ! Calc sm and sh then q_sq for the level 2 model to prepare for the HL88 fix.
        ! See Prep_for_fluxes_l2p5_pbl_approx for why the use_hl88 parameter was removed
        ! rather than given an else branch.
      my_level = 'l2'
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
          ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm_l2, sh=sh_l2, rif=rif)
      call Fill_dissip_length_scale (config_flags%pbl3d_l_opt, l_master, l_boulac, l_dissip, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      call Calc_q_sq_l2 (l_master=l_master, l_dissip=l_dissip, du_dx=du_dx, dv_dy=dv_dy, dw_dz=dw_dz, du_dy=du_dy, &
          dv_dx=dv_dx, dw_dx=dw_dx, du_dz=du_dz, dw_dy=dw_dy, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
          tf_u2=tf_u2, tf_v2=tf_v2, tf_w2=tf_w2, tf_uv=tf_uv, tf_uw=tf_uw, tf_vw=tf_vw, tf_wtv=tf_wtv, &
          ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm_l2, q_sq_hl88=q_sq_hl88, rif=rif)

      call Fill_q_sq_with_q_sq_prog (q_sq_prog, q_sq, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      my_level = 'l2p5'
        ! Calc stability functions for level 2.5 model
      call Calc_sm_sh_l2_or_l2p5 (my_level=my_level, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, ids=ids, ide=ide, &
        jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, jts=jts, jte=jte, &
        kts=kts, kte=kte, sm_l2=sm_l2, sh_l2=sh_l2, sm=sm, sh=sh, q_sq=q_sq, q_sq_hl88=q_sq_hl88, q_ratio=q_ratio, l_master_at_face=l_master)

    end subroutine Prep_for_fluxes_l2p5


    subroutine Fill_dissip_length_scale (l_opt, l_master, l_boulac, l_dissip, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      integer,                                     intent (in)  :: l_opt
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: l_dissip

      integer, intent (in) :: ids, ide, jds, jde, kds, kde, &
                              ims, ime, jms, jme, kms, kme, &
                              its, ite, jts, jte, kts, kte

        ! Local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end
      real :: l
      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      do j = j_start, j_end
        do k = kts, kte
          do i = i_start, i_end
            if (l_opt < 3) then
              l_dissip(i, k, j) = l_master(i, k, j)
            else
              l_dissip(i, k, j) = l_boulac(i, k, j)
            end if
          end do
        end do
      end do

    end subroutine Fill_dissip_length_scale


    subroutine Set_fluxes_to_min (q_sq, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, &
        tf_vw, tf_utv, tf_vtv, tf_wtv, tf_t2v, tf_ut, tf_vt, tf_wt, tf_uqv, &
        tf_vqv, tf_wqv)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                       !
        ! Purpose: Set the turbulent fluxes to the minimum val  !
        !                                                       !
        ! Author: Pedro A. Jimenez                              !
        !                                                       !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, intent (inout) :: q_sq, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw,  &
          tf_utv, tf_vtv, tf_wtv, tf_t2v, tf_ut, tf_vt, tf_wt, tf_uqv, tf_vqv, &
          tf_wqv

      q_sq = Q_SQ_MIN
      tf_u2 = TURB_FLUX_MIN
      tf_v2 = TURB_FLUX_MIN
      tf_w2 = TURB_FLUX_MIN
      tf_uv = TURB_FLUX_MIN
      tf_uw = TURB_FLUX_MIN
      tf_vw = TURB_FLUX_MIN
      tf_utv = TURB_FLUX_MIN
      tf_vtv = TURB_FLUX_MIN
      tf_wtv = TURB_FLUX_MIN
      tf_t2v = TURB_FLUX_MIN
      tf_ut = TURB_FLUX_MIN
      tf_vt = TURB_FLUX_MIN
      tf_wt = TURB_FLUX_MIN
      tf_uqv = TURB_FLUX_MIN
      tf_vqv = TURB_FLUX_MIN
      tf_wqv = TURB_FLUX_MIN

    end subroutine Set_fluxes_to_min


    subroutine Diagnose_fluxes (q_sq_at_walls_1dpbl, l_master, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz,      &
        dthetav_dx, dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, dqv_dz, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,        &
        turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_uqv, &
        turb_flux_vqv, turb_flux_wqv, tf_utv, tf_vtv, tf_wtv, tf_uqv, tf_vqv, tf_wqv, mat_cond_heat, mat_cond_moist, n_backoff,   &
        dg_t1_ratio, dg_t3_flags, dg_sk_eps, dg_n_tau, dg_qv2                                                               )

      implicit none

      real, intent (in)    :: du_dx, dv_dy, dw_dz, du_dy, dv_dx,      &
                              dw_dx, du_dz, dw_dy, dv_dz,             &
                              dthetav_dx, dthetav_dy, dthetav_dz,     &
                              dqv_dx, dqv_dy, dqv_dz
      real, intent (in)    :: q_sq_at_walls_1dpbl, l_master
      real, intent (out)   :: turb_flux_u2, turb_flux_v2, turb_flux_w2, &
                              turb_flux_uv, turb_flux_uw, turb_flux_vw, &
                              turb_flux_utheta_v, turb_flux_vtheta_v,   &
                              turb_flux_wtheta_v, turb_flux_theta2_v,   &
                              turb_flux_uqv, turb_flux_vqv, turb_flux_wqv
      real, intent (out)   :: mat_cond_heat, mat_cond_moist
      integer, intent (out) :: n_backoff
        ! Diagnostics. dg_t1_ratio is l_use/l after Tier 1 (1 = the strain limit did not
        ! bind); dg_sk_eps is the raw S k / eps the point would have run at without it;
        ! dg_n_tau is the signed N tau, negative under unstable stratification, which is
        ! where the buoyancy coupling degenerates the matrix; dg_t3_flags is the Tier 3
        ! bitmask. All are recorded before limiting so they describe the flow, not the
        ! safeguard.
      real,    intent (out) :: dg_t1_ratio, dg_t3_flags, dg_sk_eps, dg_n_tau
        ! Water vapour variance <qv'^2>, diagnosed from the moisture fluxes. Reported as a
        ! history field so that the moisture-side Cauchy-Schwarz bounds can be checked
        ! directly against turb_flux_wqv and turb_flux_w2 in the output.
      real,    intent (out) :: dg_qv2
      real (kind = SOLVER_PREC), intent (out) :: tf_utv, tf_vtv, tf_wtv, tf_uqv, tf_vqv, tf_wqv

        ! Local vars
      real (kind = SOLVER_PREC) :: q, q_sq, l, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_t2v
      real (kind = SOLVER_PREC) :: tf_qvtv, tf_qv2
      real (kind = SOLVER_PREC) :: du_dx_tmp, dv_dy_tmp, dw_dz_tmp, du_dy_tmp, dv_dx_tmp,      &
                                   dw_dx_tmp, du_dz_tmp, dw_dy_tmp, dv_dz_tmp, dthetav_dx_tmp, &
                                   dthetav_dy_tmp, dthetav_dz_tmp, dqv_dx_tmp, dqv_dy_tmp, dqv_dz_tmp
      real (kind = SOLVER_PREC) :: strain_mag, l_use, div_u
      integer :: n_try, n_t3_flags
      logical :: solve_ok

      logical, parameter :: DEBUG = .false.

        ! Convert vars from single prec to double prec
      q_sq = Working_to_solver_prec(q_sq_at_walls_1dpbl)
      q = Sqrt ( q_sq )
      l = Working_to_solver_prec(l_master)
      du_dx_tmp = Working_to_solver_prec(du_dx)
      du_dy_tmp = Working_to_solver_prec(du_dy)
      du_dz_tmp = Working_to_solver_prec(du_dz)
      dv_dx_tmp = Working_to_solver_prec(dv_dx)
      dv_dy_tmp = Working_to_solver_prec(dv_dy)
      dv_dz_tmp = Working_to_solver_prec(dv_dz)
      dw_dx_tmp = Working_to_solver_prec(dw_dx)
      dw_dy_tmp = Working_to_solver_prec(dw_dy)
      dw_dz_tmp = Working_to_solver_prec(dw_dz)
      dthetav_dx_tmp = Working_to_solver_prec(dthetav_dx)
      dthetav_dy_tmp = Working_to_solver_prec(dthetav_dy)
      dthetav_dz_tmp = Working_to_solver_prec(dthetav_dz)
      dqv_dx_tmp = Working_to_solver_prec(dqv_dx)
      dqv_dy_tmp = Working_to_solver_prec(dqv_dy)
      dqv_dz_tmp = Working_to_solver_prec(dqv_dz)

        ! ---------------------------------------------------------------------------
        ! Tier 1: limit the turbulence length scale by the strain rate.
        !
        ! The algebraic system is only meaningful while the turbulence relaxes faster
        ! than the mean gradients distort it (weak-equilibrium assumption). That same
        ! condition is what keeps A = (1/tau) I + S diagonally dominant. Bounding
        ! S k / eps <= SK_EPS_MAX therefore keeps the closure inside its own stated
        ! validity range and conditions the matrix with a single physical knob. This is
        ! the shear counterpart of the buoyancy limit l <= N_TAU_MAX q / N that
        ! Calc_l_master_algebra applies to l_master before it ever reaches here.
        !
        ! l enters both A and b, and is applied to both here, so the strain-free limit
        ! is untouched: u'2 = v'2 = w'2 = q^2 / 3 independently of l.
        ! ---------------------------------------------------------------------------
      strain_mag = Sqrt ( 2.0_SOLVER_PREC * (du_dx_tmp ** 2 + dv_dy_tmp ** 2 + dw_dz_tmp ** 2)      &
                        + (du_dy_tmp + dv_dx_tmp) ** 2 + (du_dz_tmp + dw_dx_tmp) ** 2               &
                        + (dv_dz_tmp + dw_dy_tmp) ** 2 )

      l_use = Min ( l, Real (2.0 * SK_EPS_MAX / b_1, kind = SOLVER_PREC) * q     &
                       / Max (strain_mag, Real (STRAIN_MIN, kind = SOLVER_PREC)) )

        ! S k / eps = |S| b_1 l / (2 q), from k = q^2/2 and eps = q^3/(b_1 l).
      dg_sk_eps   = Real (strain_mag * Real (b_1, kind = SOLVER_PREC) * l                     &
                          / (2.0_SOLVER_PREC * Max (q, Tiny (q))), kind = WORKING_PREC)
      dg_n_tau    = Real (Sign (Sqrt (Abs (Real (G_OVER_TREF, kind = SOLVER_PREC)             &
                                           * dthetav_dz_tmp)), dthetav_dz_tmp)                &
                          * l / Max (q, Tiny (q)), kind = WORKING_PREC)
      dg_t1_ratio = Real (l_use / Max (l, Tiny (l)), kind = WORKING_PREC)

        ! ---------------------------------------------------------------------------
        ! Tier 2: escalate locally while the solve is degenerate OR its solution is not
        ! a physically possible turbulence state.
        !
        ! Shortening l shortens the return-to-isotropy time scale, which strengthens the
        ! diagonal of A in a physically meaningful way. The escalation has a well defined
        ! endpoint: as l -> 0 the matrix becomes exactly diagonal and its solution is
        ! isotropic turbulence carrying the correct TKE, so the sequence always
        ! terminates in an admissible state rather than in a numerical artefact.
        !
        ! The acceptance test is full positive semi-definiteness of the stress tensor,
        ! not merely non negative variances. Escalating on it rather than only on solver
        ! distress matters: an outright singular A is rare, whereas a well conditioned
        ! solve returning an impossible stress state is common in strong strain. Every
        ! step of the escalation returns an exact solution of the closure at a shorter
        ! length scale, whereas the projection in Tier 3 returns a state that solves no
        ! equation, so it is worth a few extra solves to avoid reaching for it.
        ! ---------------------------------------------------------------------------
      n_backoff = 0

      attempts_mom: do n_try = 1, MAX_SOLVE_ATTEMPTS

        call Solve_turb_system (q, q_sq, l_use, du_dx_tmp, du_dy_tmp, du_dz_tmp, dv_dx_tmp, dv_dy_tmp, dv_dz_tmp, dw_dx_tmp, dw_dy_tmp, dw_dz_tmp, &
            dthetav_dx_tmp, dthetav_dy_tmp, dthetav_dz_tmp, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv, tf_t2v, &
            mat_cond_heat, solve_ok)

        if (solve_ok) then
          if (Is_realizable (tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw)) exit attempts_mom
        end if

          ! Only shorten l if another attempt follows, so that on exhaustion l_use still
          ! describes the state actually returned. Tier 3 and the moisture system both
          ! consume it.
        if (n_try < MAX_SOLVE_ATTEMPTS) then
          l_use = Real (L_BACKOFF, kind = SOLVER_PREC) * l_use
          n_backoff = n_backoff + 1
        end if

      end do attempts_mom

      if (.not. solve_ok) then
          ! Terminal state of the escalation, written out explicitly: isotropic
          ! equilibrium turbulence with the correct TKE and no organised transport.
        tf_u2  = q_sq / 3.0_SOLVER_PREC
        tf_v2  = q_sq / 3.0_SOLVER_PREC
        tf_w2  = q_sq / 3.0_SOLVER_PREC
        tf_uv  = 0.0_SOLVER_PREC
        tf_uw  = 0.0_SOLVER_PREC
        tf_vw  = 0.0_SOLVER_PREC
        tf_utv = 0.0_SOLVER_PREC
        tf_vtv = 0.0_SOLVER_PREC
        tf_wtv = 0.0_SOLVER_PREC
        tf_t2v = 0.0_SOLVER_PREC
      end if

        ! ---------------------------------------------------------------------------
        ! Tier 3: enforce the realizability constraints the exact system already obeys.
        ! Done before the moist solve, whose right hand side consumes these moments.
        ! ---------------------------------------------------------------------------
      div_u = du_dx_tmp + dv_dy_tmp + dw_dz_tmp

      call Enforce_realizability (q, q_sq, l_use, div_u, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, &
          tf_utv, tf_vtv, tf_wtv, tf_t2v, n_t3_flags)

        ! n_t3_flags is carried on into Enforce_realizability_moist below, which adds bits
        ! 32-128 to it; dg_t3_flags is set once, after both halves have run.

        ! Solve system of equations for moisture fluxes, on the length scale the
        ! momentum system actually accepted so both systems stay mutually consistent
      attempts_moist: do n_try = 1, MAX_SOLVE_ATTEMPTS

        call Solve_turb_system_moist (q, l_use, du_dx_tmp, du_dy_tmp, du_dz_tmp, dv_dx_tmp, dv_dy_tmp, dv_dz_tmp, dw_dx_tmp, dw_dy_tmp, dw_dz_tmp, dthetav_dx_tmp, &
            dthetav_dy_tmp, dthetav_dz_tmp, dqv_dx_tmp, dqv_dy_tmp, dqv_dz_tmp, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv, &
            tf_uqv, tf_vqv, tf_wqv, tf_qvtv, mat_cond_moist, solve_ok)

        if (solve_ok) exit attempts_moist

        l_use = Real (L_BACKOFF, kind = SOLVER_PREC) * l_use
        n_backoff = n_backoff + 1

      end do attempts_moist

        ! ---------------------------------------------------------------------------
        ! Tier 3, moisture side. Diagnose <qv'^2> from the moisture fluxes on the length
        ! scale the moist solve actually accepted, then apply the same realizability
        ! constraints the heat side already obeys. Until this existed the moisture fluxes
        ! were the only moments in the scheme with no realizability constraint at all.
        ! ---------------------------------------------------------------------------
      call Calc_qv_variance (q, l_use, dqv_dx_tmp, dqv_dy_tmp, dqv_dz_tmp, &
          tf_uqv, tf_vqv, tf_wqv, tf_qv2)

      call Enforce_realizability_moist (tf_u2, tf_v2, tf_w2, tf_t2v, &
          tf_uqv, tf_vqv, tf_wqv, tf_qvtv, tf_qv2, n_t3_flags)

      dg_t3_flags = Real (n_t3_flags, kind = WORKING_PREC)
      dg_qv2      = Real (tf_qv2, kind = WORKING_PREC)

        ! Convert vars from double prec to single prec
      turb_flux_u2 = Solver_to_working_prec(tf_u2)
      turb_flux_v2 = Solver_to_working_prec(tf_v2)
      turb_flux_w2 = Solver_to_working_prec(tf_w2)
      turb_flux_uv = Solver_to_working_prec(tf_uv)
      turb_flux_uw = Solver_to_working_prec(tf_uw)
      turb_flux_vw = Solver_to_working_prec(tf_vw)
      turb_flux_utheta_v = Solver_to_working_prec(tf_utv)
      turb_flux_vtheta_v = Solver_to_working_prec(tf_vtv)
      turb_flux_wtheta_v = Solver_to_working_prec(tf_wtv)
      turb_flux_theta2_v = Solver_to_working_prec(tf_t2v)
      turb_flux_uqv = Solver_to_working_prec(tf_uqv)
      turb_flux_vqv = Solver_to_working_prec(tf_vqv)
      turb_flux_wqv = Solver_to_working_prec(tf_wqv)

    end subroutine Diagnose_fluxes


    pure logical function Is_realizable (tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      ! Purpose: True when the Reynolds stress tensor is a possible covariance    !
      !          matrix, i.e. positive semi-definite.                             !
      !                                                                          !
      ! Comments: By Sylvester's criterion a symmetric 3x3 matrix is positive     !
      !           semi-definite iff all its principal minors are non negative:    !
      !           the three diagonal entries (variances), the three 2x2 minors    !
      !           (which are precisely the Cauchy-Schwarz inequalities) and the   !
      !           determinant. Checking only the variances, or only the           !
      !           variances and Cauchy-Schwarz, is necessary but not sufficient:  !
      !           a solution can satisfy every pairwise bound and still have a    !
      !           negative variance along some rotated axis.                      !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real (kind = SOLVER_PREC), intent (in) :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw

      Is_realizable = ( tf_u2 >= 0.0_SOLVER_PREC )                                       &
                .and. ( tf_v2 >= 0.0_SOLVER_PREC )                                       &
                .and. ( tf_w2 >= 0.0_SOLVER_PREC )                                       &
                .and. ( tf_u2 * tf_v2 - tf_uv ** 2 >= 0.0_SOLVER_PREC )                  &
                .and. ( tf_u2 * tf_w2 - tf_uw ** 2 >= 0.0_SOLVER_PREC )                  &
                .and. ( tf_v2 * tf_w2 - tf_vw ** 2 >= 0.0_SOLVER_PREC )                  &
                .and. ( tf_u2 * tf_v2 * tf_w2                                            &
                        - tf_u2 * tf_vw ** 2 - tf_v2 * tf_uw ** 2 - tf_w2 * tf_uv ** 2   &
                        + 2.0_SOLVER_PREC * tf_uv * tf_uw * tf_vw >= 0.0_SOLVER_PREC )

    end function Is_realizable


    pure subroutine Enforce_realizability (q, q_sq, l, div_u, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, &
        tf_utv, tf_vtv, tf_wtv, tf_t2v, t3_flags)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      ! Purpose: Restore the realizability constraints that the exact second      !
      !          moment system obeys but its numerical solution need not.         !
      !                                                                          !
      ! Comments: This is the full 3D counterpart of the HL88 criterion that      !
      !           Prep_for_fluxes_l2p5_pbl_approx applies on the approximate      !
      !           branch, and nothing here is a free parameter:                   !
      !                                                                          !
      !           1. Variances are non negative by definition.                    !
      !                                                                          !
      !           2. Rows 1-3 of the A matrix cancel exactly on columns 4-10       !
      !              (including the buoyancy column) and sum to q / (2 a_1 l) on   !
      !              columns 1-3, while                                           !
      !              b1 + b2 + b3 = q^3 / (2 a_1 l) + 3 c_1 q^2 div(U). Adding the !
      !              three rows therefore fixes the trace of the normal stresses   !
      !              exactly at q^2 (1 + 6 a_1 c_1 l div(U) / q); any departure    !
      !              from it is numerical error, not physics. For non divergent    !
      !              flow this reduces to the familiar u'2 + v'2 + w'2 = q^2.      !
      !                                                                          !
      !           3. Covariances obey the Cauchy-Schwarz inequality, e.g.         !
      !              (u'w')^2 <= u'2 w'2. These are the 2x2 principal minors.      !
      !                                                                          !
      !           4. The stress tensor as a whole is positive semi-definite. With !
      !              1 and 3 in place the only Sylvester condition still missing  !
      !              is a non negative determinant, so it is restored by shrinking !
      !              all three covariances with one common factor. That preserves  !
      !              the trace (hence the TKE) exactly and the sign and relative   !
      !              magnitude of every flux, and is a no-op wherever the tensor   !
      !              is already realizable.                                       !
      !                                                                          !
      !           Each step is a no-op on a well conditioned, already realizable  !
      !           solution.                                                       !
      !                                                                          !
      ! References: Helfand and Labraga (1988, JAS), Schumann (1977, Phys Fluids) !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real (kind = SOLVER_PREC), intent (in)    :: q, q_sq, l, div_u
      real (kind = SOLVER_PREC), intent (inout) :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, &
                                                   tf_utv, tf_vtv, tf_wtv, tf_t2v
        ! Diagnostic bitmask recording which steps actually changed the answer, so that a
        ! run can distinguish "Tier 3 ran" from "Tier 3 had to do something":
        !   1  variance floor clipped a negative variance
        !   2  trace rescale moved the normal stresses by more than TIER3_TOL
        !   4  Cauchy-Schwarz clipped a momentum covariance
        !   8  determinant shrink fired
        !  16  theta_v variance floor or heat-flux Cauchy-Schwarz clipped
      integer,                   intent (out)   :: t3_flags

      real (kind = SOLVER_PREC) :: trace, trace_target
      real (kind = SOLVER_PREC) :: det_0, det_2, det_3, gam, gam_lo, gam_hi
      real (kind = SOLVER_PREC) :: uv_in, uw_in, vw_in, t2v_in, utv_in, vtv_in, wtv_in
      integer :: n_bis
        ! Relative tolerance for calling the trace rescale a real correction rather than
        ! round-off. 1e-10 was too tight: the trace identity is recovered from the solve
        ! only to accumulated round-off, so it flagged essentially every point and told
        ! us nothing. 1e-6 is still far below any physically meaningful rescaling.
      real (kind = SOLVER_PREC), parameter :: TIER3_TOL = 1.0E-6_SOLVER_PREC

      t3_flags = 0

        ! 1. Variances are non negative
      if (tf_u2 < 0.0_SOLVER_PREC .or. tf_v2 < 0.0_SOLVER_PREC .or. tf_w2 < 0.0_SOLVER_PREC) &
          t3_flags = t3_flags + 1
      tf_u2 = Max (tf_u2, 0.0_SOLVER_PREC)
      tf_v2 = Max (tf_v2, 0.0_SOLVER_PREC)
      tf_w2 = Max (tf_w2, 0.0_SOLVER_PREC)

        ! 2. Restore the exact trace implied by the system itself
      trace_target = q_sq * ( 1.0_SOLVER_PREC                                                  &
          + Real (6.0 * a_1 * c_1, kind = SOLVER_PREC) * l * div_u / Max (q, Tiny (q)) )
      trace_target = Max (trace_target, 0.0_SOLVER_PREC)

      trace = tf_u2 + tf_v2 + tf_w2

      if (Abs (trace - trace_target) > TIER3_TOL * Max (trace_target, TIER3_TOL)) &
          t3_flags = t3_flags + 2

      if (trace > 0.0_SOLVER_PREC) then
        tf_u2 = tf_u2 * trace_target / trace
        tf_v2 = tf_v2 * trace_target / trace
        tf_w2 = tf_w2 * trace_target / trace
      else
          ! All three normal stresses were clipped away: fall back to isotropy
        tf_u2 = trace_target / 3.0_SOLVER_PREC
        tf_v2 = trace_target / 3.0_SOLVER_PREC
        tf_w2 = trace_target / 3.0_SOLVER_PREC
      end if

        ! 3. Cauchy-Schwarz on the momentum covariances
      uv_in = tf_uv ; uw_in = tf_uw ; vw_in = tf_vw
      tf_uv = Sign (Min (Abs (tf_uv), Sqrt (tf_u2 * tf_v2)), tf_uv)
      tf_uw = Sign (Min (Abs (tf_uw), Sqrt (tf_u2 * tf_w2)), tf_uw)
      tf_vw = Sign (Min (Abs (tf_vw), Sqrt (tf_v2 * tf_w2)), tf_vw)
      if (tf_uv /= uv_in .or. tf_uw /= uw_in .or. tf_vw /= vw_in) t3_flags = t3_flags + 4

        ! 4. Positive semi-definiteness of the stress tensor as a whole.
        !
        ! Scaling the covariances by gamma makes the determinant the cubic
        ! det(gamma) = det_0 - det_2 gamma^2 + det_3 gamma^3, which is non negative at
        ! gamma = 0 because step 1 left the variances non negative. Bisection keeping
        ! det(gam_lo) >= 0 therefore always returns an admissible factor.
      det_0 = tf_u2 * tf_v2 * tf_w2
      det_2 = tf_u2 * tf_vw ** 2 + tf_v2 * tf_uw ** 2 + tf_w2 * tf_uv ** 2
      det_3 = 2.0_SOLVER_PREC * tf_uv * tf_uw * tf_vw

      if (det_0 - det_2 + det_3 < 0.0_SOLVER_PREC) then

        gam_lo = 0.0_SOLVER_PREC
        gam_hi = 1.0_SOLVER_PREC

        do n_bis = 1, N_PSD_BISECT
          gam = 0.5_SOLVER_PREC * (gam_lo + gam_hi)
          if (det_0 - det_2 * gam ** 2 + det_3 * gam ** 3 >= 0.0_SOLVER_PREC) then
            gam_lo = gam
          else
            gam_hi = gam
          end if
        end do

        tf_uv = gam_lo * tf_uv
        tf_uw = gam_lo * tf_uw
        tf_vw = gam_lo * tf_vw

        t3_flags = t3_flags + 8

      end if

        ! 5. Same for the theta_v variance and the buoyancy fluxes
      t2v_in = tf_t2v ; utv_in = tf_utv ; vtv_in = tf_vtv ; wtv_in = tf_wtv
      tf_t2v = Max (tf_t2v, 0.0_SOLVER_PREC)

      tf_utv = Sign (Min (Abs (tf_utv), Sqrt (tf_u2 * tf_t2v)), tf_utv)
      tf_vtv = Sign (Min (Abs (tf_vtv), Sqrt (tf_v2 * tf_t2v)), tf_vtv)
      tf_wtv = Sign (Min (Abs (tf_wtv), Sqrt (tf_w2 * tf_t2v)), tf_wtv)
      if (tf_t2v /= t2v_in .or. tf_utv /= utv_in .or. tf_vtv /= vtv_in .or. tf_wtv /= wtv_in) &
          t3_flags = t3_flags + 16

    end subroutine Enforce_realizability


    pure function Working_to_solver_prec (var)

      implicit none

      real (kind = WORKING_PREC), intent(in) :: var
      real (kind = SOLVER_PREC)              :: Working_to_solver_prec

      working_to_solver_prec = Real (var, kind = SOLVER_PREC)

    end function Working_to_solver_prec


    pure function Solver_to_working_prec (var)

      implicit none

      real (kind = SOLVER_PREC), intent(in) :: var
      real (kind = WORKING_PREC)            :: Solver_to_working_prec

      solver_to_working_prec = Real (var, kind = WORKING_PREC)

    end function Solver_to_working_prec


    subroutine Solve_turb_system (q, q_sq, l, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, &
              dthetav_dx, dthetav_dy, dthetav_dz, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv, tf_t2v, &
              mat_cond, solve_ok)

      implicit none

      real (kind = SOLVER_PREC), intent (in)    :: q, q_sq, l
      real (kind = SOLVER_PREC), intent (in)    :: du_dx, dv_dy, dw_dz, du_dy, dv_dx,      &
                                                   dw_dx, du_dz, dw_dy, dv_dz,             &
                                                   dthetav_dx, dthetav_dy, dthetav_dz
      real,                      intent (out)   :: mat_cond
      logical,                   intent (out)   :: solve_ok
      real (kind = SOLVER_PREC), intent (out)   :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv, tf_t2v

        ! Local vars
      character (len = 1) :: equed
      integer, parameter   :: N_VARS = 10
      integer :: ipiv(N_VARS)
      integer :: info
      integer, dimension(N_VARS) :: iwork
      real (kind = SOLVER_PREC) :: rcond, ferr, berr
      real (kind = SOLVER_PREC), dimension(4*N_VARS) :: work
      real (kind = SOLVER_PREC), dimension(N_VARS) :: rsf, csf
        ! Fixed size rather than allocatable: this routine runs once per grid point per time
        ! step, so heap traffic here is pure overhead. N_VARS is a parameter, so the shapes
        ! are known at compile time and these cost nothing.
      real (kind = SOLVER_PREC), dimension(N_VARS) :: b, x
      real (kind = SOLVER_PREC), dimension(N_VARS, N_VARS) :: a, af

      external dgesvx

        ! Fills in the B matrix
      call Fill_in_b_vector (b, q, q_sq, l, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz)

        ! Fills in the A matrix
      call Fill_in_a_matrix (a, q, q_sq, l, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, &
          dthetav_dx, dthetav_dy, dthetav_dz)

        ! Compute solution to system of linear equations.
        ! FACT = 'E' equilibrates A before factoring. This is not a physical change: the
        ! columns of A carry mixed units (m2 s-2 for the momentum moments, K m s-1 for the
        ! heat fluxes, K2 for the theta_v variance), so the raw system is badly scaled by
        ! construction and rcond is dominated by units rather than by the physics. With
        ! FACT = 'N' (the previous setting) dgesvx performs no equilibration at all.
      call dgesvx ('E', 'N', N_VARS, 1, a, N_VARS, af, N_VARS, ipiv, equed, rsf, csf, b, N_VARS, x, N_VARS, rcond, ferr, berr, work, iwork, info)

      if (rcond > 0.0_SOLVER_PREC) then
        mat_cond = Real (1.0_SOLVER_PREC / rcond, kind = WORKING_PREC)
      else
        mat_cond = Huge (mat_cond)
      end if

        ! INFO in [1, N] means U(i,i) is exactly zero and X was *not* computed, i.e. x()
        ! holds undefined memory - it must never be used. INFO = N+1 means the matrix is
        ! singular to working precision: x is computed but not trustworthy.
      solve_ok = (info == 0) .and. (mat_cond <= COND_MAX)

      if (solve_ok) then
        tf_u2 = x(1)
        tf_v2 = x(2)
        tf_w2 = x(3)
        tf_uv = x(4)
        tf_uw = x(5)
        tf_vw = x(6)
        tf_utv = x(7)
        tf_vtv = x(8)
        tf_wtv = x(9)
        tf_t2v = x(10)
      else
        tf_u2  = 0.0_SOLVER_PREC
        tf_v2  = 0.0_SOLVER_PREC
        tf_w2  = 0.0_SOLVER_PREC
        tf_uv  = 0.0_SOLVER_PREC
        tf_uw  = 0.0_SOLVER_PREC
        tf_vw  = 0.0_SOLVER_PREC
        tf_utv = 0.0_SOLVER_PREC
        tf_vtv = 0.0_SOLVER_PREC
        tf_wtv = 0.0_SOLVER_PREC
        tf_t2v = 0.0_SOLVER_PREC
      end if

    end subroutine Solve_turb_system


    subroutine Solve_turb_system_moist (q, l, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, dthetav_dx, &
              dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, dqv_dz, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv, &
              tf_uqv, tf_vqv, tf_wqv, tf_qvtv, mat_cond, solve_ok)

      implicit none

      real (kind = SOLVER_PREC), intent (in)    :: q, l
      real (kind = SOLVER_PREC), intent (in)    :: du_dx, dv_dy, dw_dz, du_dy, dv_dx,      &
                                                   dw_dx, du_dz, dw_dy, dv_dz,             &
                                                   dthetav_dx, dthetav_dy, dthetav_dz,     &
                                                   dqv_dx, dqv_dy, dqv_dz
      real (kind = SOLVER_PREC), intent (in)    :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv
      real (kind = SOLVER_PREC), intent (out)   :: tf_uqv, tf_vqv, tf_wqv
        ! x(4) is the moisture-heat covariance <qv' thetav'>. It was solved for and then
        ! discarded; it is returned now because the Cauchy-Schwarz bound
        ! <qv' thetav'>^2 <= <qv'^2> <thetav'^2> is one of the realizability constraints
        ! restored by Enforce_realizability_moist.
      real (kind = SOLVER_PREC), intent (out)   :: tf_qvtv
      real,                      intent (out)   :: mat_cond
      logical,                   intent (out)   :: solve_ok

        ! Local vars
      character (len = 1) :: equed
      integer, parameter   :: N_VARS = 4
      integer :: ipiv(N_VARS)
      integer :: info
      integer, dimension(N_VARS) :: iwork
      real (kind = SOLVER_PREC) :: rcond, ferr, berr
      real (kind = SOLVER_PREC), dimension(4*N_VARS) :: work
      real (kind = SOLVER_PREC), dimension(N_VARS) :: rsf, csf
        ! Fixed size rather than allocatable, for the same reason as in Solve_turb_system.
      real (kind = SOLVER_PREC), dimension(N_VARS) :: b, x
      real (kind = SOLVER_PREC), dimension(N_VARS, N_VARS) :: a, af

      external dgesvx

        ! Fills in the B matrix
      call Fill_in_b_vector_moist (b, dqv_dx, dqv_dy, dqv_dz, tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv)

        ! Fills in the A matrix
      call Fill_in_a_matrix_moist (a, q, l, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, &
          dthetav_dx, dthetav_dy, dthetav_dz)

        ! Compute solution to system of linear equations (see Solve_turb_system for why
        ! FACT = 'E'; this system mixes kg kg-1 m s-1 with K kg kg-1 and is likewise
        ! badly scaled by construction).
      call dgesvx ('E', 'N', N_VARS, 1, a, N_VARS, af, N_VARS, ipiv, equed, rsf, csf, b, N_VARS, x, N_VARS, rcond, ferr, berr, work, iwork, info)

      if (rcond > 0.0_SOLVER_PREC) then
        mat_cond = Real (1.0_SOLVER_PREC / rcond, kind = WORKING_PREC)
      else
        mat_cond = Huge (mat_cond)
      end if

      solve_ok = (info == 0) .and. (mat_cond <= COND_MAX)

      if (solve_ok) then
        tf_uqv  = x(1)
        tf_vqv  = x(2)
        tf_wqv  = x(3)
        tf_qvtv = x(4)
      else
        tf_uqv  = 0.0_SOLVER_PREC
        tf_vqv  = 0.0_SOLVER_PREC
        tf_wqv  = 0.0_SOLVER_PREC
        tf_qvtv = 0.0_SOLVER_PREC
      end if

    end subroutine Solve_turb_system_moist


    pure subroutine Calc_qv_variance (q, l, dqv_dx, dqv_dy, dqv_dz, tf_uqv, tf_vqv, tf_wqv, tf_qv2)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      ! Purpose: Diagnose the water vapour variance <qv'^2> from the moisture     !
      !          fluxes, so that the moisture side of the closure has the same     !
      !          realizability constraints as the heat side.                       !
      !                                                                          !
      ! Comments: The steady, weak-equilibrium <qv'^2> budget is the exact         !
      !           analogue of the <thetav'^2> equation already carried as row 10   !
      !           of the momentum/heat system (Fill_in_a_matrix):                  !
      !                                                                          !
      !             <u_j' qv'> dQv/dx_j  +  q <qv'^2> / (b_2 l)  =  0              !
      !                                                                          !
      !           production against the mean moisture gradient balanced by        !
      !           dissipation at rate q / (b_2 l), giving                          !
      !                                                                          !
      !             <qv'^2> = - (b_2 l / q) * <u_j' qv'> dQv/dx_j                  !
      !                                                                          !
      !           In the 1D limit <w'qv'> = -l q Sh dQv/dz this reduces to         !
      !           <qv'^2> = b_2 l^2 Sh (dQv/dz)^2, which is exactly the form the    !
      !           approximate branch already uses for <thetav'^2>                  !
      !           (diag_th2v_pbl_approx), so the two branches agree by             !
      !           construction.                                                    !
      !                                                                          !
      !           Why this is not a fifth row of the moist system: as a row it     !
      !           would read (dQv/dx, dQv/dy, dQv/dz, 0, q/(b_2 l)) with a zero    !
      !           right hand side, and no other row of that system has an entry    !
      !           in the <qv'^2> column - nothing couples back to it, because the   !
      !           buoyancy term in the <w'qv'> equation goes through <qv' thetav'>, !
      !           which is already column 4. The 5x5 system is therefore block      !
      !           triangular and its first four unknowns are identical to the 4x4   !
      !           solution. Solving it in closed form here is algebraically exact,  !
      !           costs nothing, and - unlike enlarging the matrix - cannot perturb !
      !           the existing fluxes through dgesvx's equilibration (FACT = 'E'    !
      !           rescales rows and columns, so adding a row would change the       !
      !           computed x(1:4) at round-off level for no benefit).               !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real (kind = SOLVER_PREC), intent (in)  :: q, l, dqv_dx, dqv_dy, dqv_dz
      real (kind = SOLVER_PREC), intent (in)  :: tf_uqv, tf_vqv, tf_wqv
      real (kind = SOLVER_PREC), intent (out) :: tf_qv2

      tf_qv2 = - Real (b_2, kind = SOLVER_PREC) * l / Max (q, Tiny (q))                       &
               * (dqv_dx * tf_uqv + dqv_dy * tf_vqv + dqv_dz * tf_wqv)

    end subroutine Calc_qv_variance


    pure subroutine Enforce_realizability_moist (tf_u2, tf_v2, tf_w2, tf_t2v, &
        tf_uqv, tf_vqv, tf_wqv, tf_qvtv, tf_qv2, t3_flags)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      ! Purpose: The moisture counterpart of step 5 of Enforce_realizability.     !
      !                                                                          !
      ! Comments: Before this existed the moisture fluxes were the only moments   !
      !           in the scheme under no realizability constraint of any kind:    !
      !           the 4x4 moist system carries no <qv'^2>, so there was nothing   !
      !           to bound them against and the implied correlation coefficient   !
      !           <w'qv'> / sqrt(<w'^2><qv'^2>) could exceed one without any      !
      !           part of the code noticing.                                     !
      !                                                                          !
      !           With <qv'^2> available from Calc_qv_variance the same three     !
      !           constraints the heat side already obeys can be applied:         !
      !                                                                          !
      !             1. <qv'^2> >= 0                                              !
      !             2. <u_i' qv'>^2 <= <u_i'^2> <qv'^2>   (i = u, v, w)           !
      !             3. <qv' thetav'>^2 <= <qv'^2> <thetav'^2>                    !
      !                                                                          !
      !           In the 1D limit all three are inactive - substituting the       !
      !           gradient-diffusion forms turns 2 into a condition on the        !
      !           closure constants alone, which they satisfy - so this is a      !
      !           no-op wherever the flux is aligned with the gradient. It        !
      !           engages where the moisture flux vector and the moisture         !
      !           gradient are misaligned, i.e. where transport is set by the     !
      !           3D stress tensor rather than by the local gradient. Over        !
      !           complex terrain, a valley moisture gradient combined with a     !
      !           slope flow is exactly that situation.                          !
      !                                                                          !
      !           <qv'^2> is diagnosed from the fluxes, so clipping a flux makes  !
      !           it stale. One pass is applied rather than iterating, matching   !
      !           step 5 of Enforce_realizability, which has the same structure   !
      !           for <thetav'^2>. Clipping only ever reduces |flux|, so the pass !
      !           is a contraction and cannot introduce a new violation of the    !
      !           bound it just enforced.                                        !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real (kind = SOLVER_PREC), intent (in)    :: tf_u2, tf_v2, tf_w2, tf_t2v
      real (kind = SOLVER_PREC), intent (inout) :: tf_uqv, tf_vqv, tf_wqv, tf_qvtv, tf_qv2
        ! Bitmask, continuing the numbering of Enforce_realizability:
        !   32  <qv'^2> was negative and has been floored at zero
        !   64  a moisture flux was clipped by Cauchy-Schwarz
        !  128  the moisture-heat covariance was clipped by Cauchy-Schwarz
      integer,                   intent (inout) :: t3_flags

      real (kind = SOLVER_PREC) :: uqv_in, vqv_in, wqv_in, qvtv_in

      if (tf_qv2 < 0.0_SOLVER_PREC) then
        tf_qv2 = 0.0_SOLVER_PREC
        t3_flags = t3_flags + 32
      end if

      uqv_in = tf_uqv ; vqv_in = tf_vqv ; wqv_in = tf_wqv
      tf_uqv = Sign (Min (Abs (tf_uqv), Sqrt (tf_u2 * tf_qv2)), tf_uqv)
      tf_vqv = Sign (Min (Abs (tf_vqv), Sqrt (tf_v2 * tf_qv2)), tf_vqv)
      tf_wqv = Sign (Min (Abs (tf_wqv), Sqrt (tf_w2 * tf_qv2)), tf_wqv)
      if (tf_uqv /= uqv_in .or. tf_vqv /= vqv_in .or. tf_wqv /= wqv_in) t3_flags = t3_flags + 64

      qvtv_in = tf_qvtv
      tf_qvtv = Sign (Min (Abs (tf_qvtv), Sqrt (tf_qv2 * tf_t2v)), tf_qvtv)
      if (tf_qvtv /= qvtv_in) t3_flags = t3_flags + 128

    end subroutine Enforce_realizability_moist


    subroutine Fill_in_b_vector (b, q, q_sq, l, u_x, u_y, u_z, v_x, &
        v_y, v_z, w_x, w_y, w_z)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Fills in the vector b with the indenpendent terms         !
      !                                                                    !
      ! Author: Pedro A. Jimenez                                           !
      !                                                                    !
      ! Comments: A * X = B wherein X are the tubulent fluxes of momentum, !
      !           theta_v, and theta2_v                                    !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


      implicit none

      real (kind = SOLVER_PREC), intent(in) :: q, q_sq, l
      real (kind = SOLVER_PREC), intent(in) :: u_x, u_y, u_z, v_x, v_y, v_z, w_x, w_y, w_z
      real (kind = SOLVER_PREC), dimension(:), intent(inout) :: b(:)

      b = 0.0
      b(1) = Real (q ** 3.0 / (6.0 * a_1 * l) + 3.0 * c_1 * q_sq * u_x, kind = SOLVER_PREC)
      b(2) = Real (q ** 3.0 / (6.0 * a_1 * l) + 3.0 * c_1 * q_sq * v_y, kind = SOLVER_PREC)
      b(3) = Real (q ** 3.0 / (6.0 * a_1 * l) + 3.0 * c_1 * q_sq * w_z, kind = SOLVER_PREC)
      b(4) = Real (c_1 * q_sq * (v_x + u_y), kind = SOLVER_PREC)
      b(5) = Real (c_1 * q_sq * (w_x + u_z), kind = SOLVER_PREC)
      b(6) = Real (c_1 * q_sq * (w_y + v_z), kind = SOLVER_PREC)

    end subroutine Fill_in_b_vector


    subroutine Fill_in_b_vector_moist (b, qv_x, qv_y, qv_z, tf_u2, tf_v2, tf_w2, tf_uv, &
        tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv)

        implicit none

      real (kind = SOLVER_PREC), intent(in) :: qv_x, qv_y, qv_z
      real (kind = SOLVER_PREC), intent(in) :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_utv, tf_vtv, tf_wtv
      real (kind = SOLVER_PREC), dimension(:), intent(inout) :: b(:)

      b = 0.0
      b(1) = Real (- (qv_x * tf_u2 + qv_y * tf_uv + qv_z * tf_uw), kind = SOLVER_PREC)
      b(2) = Real (- (qv_y * tf_v2 + qv_x * tf_uv + qv_z * tf_vw), kind = SOLVER_PREC)
      b(3) = Real (- (qv_z * tf_w2 + qv_x * tf_uw + qv_y * tf_vw), kind = SOLVER_PREC)
      b(4) = Real (- (qv_x * tf_utv + qv_y * tf_vtv + qv_z * tf_wtv), kind = SOLVER_PREC)

    end subroutine Fill_in_b_vector_moist


    subroutine Fill_in_a_matrix (a, q, q_sq, l, u_x, u_y, u_z, v_x, v_y, &
        v_z, w_x, w_y, w_z, tv_x, tv_y, tv_z)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Fills in the coefficients of the A Matrix                 !
      !                                                                    !
      ! Author: Pedro A. Jimenez                                           !
      !                                                                    !
      ! Comments: A * X = B wherein X are the tubulent fluxes of momentum, !
      !           theta_v, and theta2_v                                    !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!~!!!!!!

      implicit none

      real (kind = SOLVER_PREC), dimension(:, :), intent(inout) :: a(:, :)
      real (kind = SOLVER_PREC), intent(in) :: q, q_sq, l
      real (kind = SOLVER_PREC), intent(in) :: u_x, u_y, u_z, v_x, v_y, v_z, w_x, w_y, w_z, &
          tv_x, tv_y, tv_z

      a = 0.0

         ! u2 equation
      a(1, 1) = Real (q / (2.0 * a_1 * l) + 2.0 * u_x, kind = SOLVER_PREC)
      a(1, 2) = Real (- v_y, kind = SOLVER_PREC)
      a(1, 3) = Real (- w_z, kind = SOLVER_PREC)
      a(1, 4) = Real (2.0 * u_y - v_x, kind = SOLVER_PREC)
      a(1, 5) = Real (2.0 * u_z - w_x, kind = SOLVER_PREC)
      a(1, 6) = Real (- v_z - w_y, kind = SOLVER_PREC)
      a(1, 9) = Real (G_OVER_TREF, kind = SOLVER_PREC)

         ! v2 equation
      a(2, 1) = Real (- u_x, kind = SOLVER_PREC)
      a(2, 2) = Real (q / (2.0 * a_1 * l) + 2.0 * v_y, kind = SOLVER_PREC)
      a(2, 3) = Real (- w_z, kind = SOLVER_PREC)
      a(2, 4) = Real (2.0 * v_x - u_y, kind = SOLVER_PREC)
      a(2, 5) = Real (- u_z - w_x, kind = SOLVER_PREC)
      a(2, 6) = Real (2.0 * v_z - w_y, kind = SOLVER_PREC)
      a(2, 9) = Real (G_OVER_TREF, kind = SOLVER_PREC)

         ! w2 equation
      a(3, 1) = Real (- u_x, kind = SOLVER_PREC)
      a(3, 2) = Real (- v_y, kind = SOLVER_PREC)
      a(3, 3) = Real (q / (2.0 * a_1 * l) + 2.0 * w_z, kind = SOLVER_PREC)
      a(3, 4) = Real (- u_y - v_x, kind = SOLVER_PREC)
      a(3, 5) = Real (2.0 * w_x - u_z, kind = SOLVER_PREC)
      a(3, 6) = Real (2.0 * w_y - v_z, kind = SOLVER_PREC)
      a(3, 9) = Real (- 2.0 * G_OVER_TREF, kind = SOLVER_PREC)

         ! uv equation
      a(4, 1) = Real (v_x, kind = SOLVER_PREC)
      a(4, 2) = Real (u_y, kind = SOLVER_PREC)
      a(4, 4) = Real (q / (3.0 * a_1 * l) + u_x + v_y, kind = SOLVER_PREC)
      a(4, 5) = Real (v_z, kind = SOLVER_PREC)
      a(4, 6) = Real (u_z, kind = SOLVER_PREC)

       ! uw equation
      a(5, 1) = Real (w_x, kind = SOLVER_PREC)
      a(5, 3) = Real (u_z, kind = SOLVER_PREC)
      a(5, 4) = Real (w_y, kind = SOLVER_PREC)
      a(5, 5) = Real (q / (3.0 * a_1 * l) + w_z + u_x, kind = SOLVER_PREC)
      a(5, 6) = Real (u_y, kind = SOLVER_PREC)
      a(5, 7) = Real (- G_OVER_TREF, kind = SOLVER_PREC)

         ! vw equation
      a(6, 2) = Real (w_y, kind = SOLVER_PREC)
      a(6, 3) = Real (v_z, kind = SOLVER_PREC)
      a(6, 4) = Real (w_x, kind = SOLVER_PREC)
      a(6, 5) = Real (v_x, kind = SOLVER_PREC)
      a(6, 6) = Real (q / (3.0 * a_1 * l) + w_z + v_y, kind = SOLVER_PREC)
      a(6, 8) = Real (- G_OVER_TREF, kind = SOLVER_PREC)

         ! ut_v equation
      a(7, 1) = Real (tv_x, kind = SOLVER_PREC)
      a(7, 4) = Real (tv_y, kind = SOLVER_PREC)
      a(7, 5) = Real (tv_z, kind = SOLVER_PREC)
      a(7, 7) = Real (q / (3.0 * a_2 * l) + u_x, kind = SOLVER_PREC)
      a(7, 8) = Real (u_y, kind = SOLVER_PREC)
      a(7, 9) = Real (u_z, kind = SOLVER_PREC)

         ! vt_v equation
      a(8, 2) = Real (tv_y, kind = SOLVER_PREC)
      a(8, 4) = Real (tv_x, kind = SOLVER_PREC)
      a(8, 6) = Real (tv_z, kind = SOLVER_PREC)
      a(8, 7) = Real (v_x, kind = SOLVER_PREC)
      a(8, 8) = Real (q / (3.0 * a_2 * l) + v_y, kind = SOLVER_PREC)
      a(8, 9) = Real (v_z, kind = SOLVER_PREC)

         ! wt_v equation
      a(9, 3) = Real (tv_z, kind = SOLVER_PREC)
      a(9, 5) = Real (tv_x, kind = SOLVER_PREC)
      a(9, 6) = Real (tv_y, kind = SOLVER_PREC)
      a(9, 7) = Real (w_x, kind = SOLVER_PREC)
      a(9, 8) = Real (w_y, kind = SOLVER_PREC)
      a(9, 9) = Real (q / (3.0 * a_2 * l) + w_z, kind = SOLVER_PREC)
      a(9, 10) = Real (- G_OVER_TREF, kind = SOLVER_PREC)

         ! tt_v equation
      a(10, 7) = Real (tv_x, kind = SOLVER_PREC)
      a(10, 8) = Real (tv_y, kind = SOLVER_PREC)
      a(10, 9) = Real (tv_z, kind = SOLVER_PREC)
      a(10, 10) = Real (q / (b_2 * l), kind = SOLVER_PREC)

    end subroutine Fill_in_a_matrix


    subroutine Fill_in_a_matrix_moist (a, q, l, u_x, u_y, u_z, v_x, v_y, v_z, &
        w_x, w_y, w_z, tv_x, tv_y, tv_z)

      implicit none

      real (kind = SOLVER_PREC), dimension(:, :), intent(inout) :: a(:, :)
      real (kind = SOLVER_PREC), intent (in) :: q, l
      real (kind = SOLVER_PREC), intent (in) :: u_x, u_y, u_z, v_x, v_y, v_z, w_x, &
          w_y, w_z, tv_x, tv_y, tv_z

      a = 0.0

        ! ur equation
      a(1, 1) = Real (q / (3.0 * a_2 * l) + u_x, kind = SOLVER_PREC)
      a(1, 2) = Real (u_y, kind = SOLVER_PREC)
      a(1, 3) = Real (u_z, kind = SOLVER_PREC)
      a(1, 4) = 0.0

        ! vr equation
      a(2, 1) = Real (v_x, kind = SOLVER_PREC)
      a(2, 2) = Real (q / (3.0 * a_2 * l) + v_y, kind = SOLVER_PREC)
      a(2, 3) = Real (v_z, kind = SOLVER_PREC)
      a(2, 4) = 0.0

        ! wr equation
      a(3, 1) = Real (w_x, kind = SOLVER_PREC)
      a(3, 2) = Real (w_y, kind = SOLVER_PREC)
      a(3, 3) = Real (q / (3.0 * a_2 * l) + w_z, kind = SOLVER_PREC)
      a(3, 4) = Real (-G_OVER_TREF, kind = SOLVER_PREC)

        ! rthetav equation
      a(4, 1) = Real (tv_x, kind = SOLVER_PREC)
      a(4, 2) = Real (tv_y, kind = SOLVER_PREC)
      a(4, 3) = Real (tv_z, kind = SOLVER_PREC)
      a(4, 4) = Real (2.0 * q / (b_2 * l), kind = SOLVER_PREC)

    end subroutine Fill_in_a_matrix_moist


    subroutine Calc_heat_flux (th2, qv, fnm, fnp, i, j, k, tf_utv, &
        tf_vtv, tf_wtv, tf_uqv, tf_vqv, tf_wqv, tf_ut, tf_vt, tf_wt, &
        ims, ime, jms, jme, kms, kme)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                             !
      ! Purpose: Calc heat fluxes based on the moist fluses and     !
      !          virtual potential temperature fluxes               !
      !                                                             !
      ! Author: Pedro A. Jimenez                                    !
      !                                                             !
      ! Reference: YM75 (Eq. A13)                                   !
      !                                                             !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer, intent(in) :: i, k, j, ims, ime, jms, jme, kms, kme
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: th2, qv
      real, dimension (kms:kme), intent (in) :: fnm, fnp
      real (kind = SOLVER_PREC), intent(in) :: tf_utv, tf_vtv, tf_wtv, &
          tf_uqv, tf_vqv, tf_wqv
      real, intent(out) :: tf_ut, tf_vt, tf_wt

        ! Local vars
      real :: th_wall, qv_wall

      th_wall = T0 + fnm(k) * th2(i, k, j) + fnp(k) * th2(i, k - 1, j)
      qv_wall = fnm(k) * qv(i, k, j) + fnp(k) * qv(i, k - 1, j)

      tf_ut = Real ((tf_utv - P608 * th_wall * tf_uqv) / (1.0 + P608 * qv_wall), &
          kind = WORKING_PREC)

      tf_vt = Real ((tf_vtv - P608 * th_wall * tf_vqv) / (1.0 + P608 * qv_wall), &
          kind = WORKING_PREC)

      tf_wt = Real ((tf_wtv - P608 * th_wall * tf_wqv) / (1.0 + P608 * qv_wall), &
          kind = WORKING_PREC)

    end subroutine Calc_heat_flux


    subroutine Diagnose_fluxes_pbl_approx (do_scalar_mix, ss, nsteps, fnm, fnp, t, qv, ust, hfx, qfx, sm_tilde, sh_tilde, &
              sm_l2, sh_l2, rif, q_sq, q_sq_hl88, q_ratio, l_master, du_dz, dv_dz, dthetav_dz, dqv_dz, dqc_dz, &
              dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz, &
              u2, v2, w2, uv, uw, vw, uthv, vthv, wthv, th2v, uqv, vqv, wqv, uth, vth, wth, &
              uqc, vqc, wqc, uqr, vqr, wqr, uqi, vqi, wqi, uqs, vqs, wqs, uqg, vqg, wqg, uqnc, vqnc, wqnc, &
              uqnr, vqnr, wqnr, uqni, vqni, wqni, uqnwfa, vqnwfa, wqnwfa, uqnifa, vqnifa, wqnifa, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      integer, intent (in)                                        :: do_scalar_mix, ss, nsteps
      real, dimension (kms:kme),                   intent (in)    :: fnm, fnp
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz, dqv_dz, &
          dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: t, qv
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: u2, v2, w2, &
          uv, uw, vw, uthv, vthv, wthv, th2v, uqv, vqv, wqv, uth, vth, wth, &
          uqc, vqc, wqc, uqr, vqr, wqr, uqi, vqi, wqi, uqs, vqs, wqs, uqg, vqg, wqg, &
          uqnc, vqnc, wqnc, uqnr, vqnr, wqnr, uqni, vqni, wqni, uqnwfa, vqnwfa, wqnwfa, uqnifa, vqnifa, wqnifa
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: sm_tilde, sh_tilde, rif
      real, dimension (its:ite, kts:kte, jts:jte), optional, intent (in)  :: q_ratio, q_sq_hl88, sm_l2, sh_l2
      real, dimension (ims:ime, jms:jme),          intent (in)  :: ust, hfx, qfx
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real :: qsq, l, sm, sh, ri, dudz, dvdz, dthvdz, dqvdz, dqcdz, dqrdz, dqidz, dqsdz, dqgdz, &
              dqncdz, dqnrdz, dqnidz, dqnwfadz, dqnifadz
      real :: t_wall, qv_wall
      real :: dxm, dym, tmpzx, tmpzy, sf_alpha
      real :: c_p, u1, v1, wind_speed, ust_sq
      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)

      j_loop: do j = j_start, j_end
        k_loop: do k = kts + 1, ktf
          i_loop: do i = i_start, i_end

            if_low_q_sq: if (q_sq(i, k, j) > Q_SQ_MIN) then

                ! Save temporary scalars
              qsq = q_sq(i, k, j)
              sm = sm_tilde(i, k, j)
              sh = sh_tilde(i, k, j)
              l = l_master(i, k, j)
              ri = rif(i, k, j)
              dudz = du_dz(i, k, j)
              dvdz = dv_dz(i, k, j)
              dthvdz = dthetav_dz(i, k, j)
              dqvdz = dqv_dz(i, k, j)

                ! Eq. 27 MY82
              uw(i, k, j) = Diag_uw_pbl_approx (qsq, l, sm, dudz)
              vw(i, k, j) = Diag_vw_pbl_approx (qsq, l, sm, dvdz)
              uv(i, k, j) = Diag_uv_pbl_approx (qsq, l, dudz, dvdz, uw(i, k, j), vw(i, k, j))

                ! Eq. 28 MY82
              uthv(i, k, j) = Diag_uthv_pbl_approx (l, sh, sm, dthvdz, dudz)
              vthv(i, k, j) = Diag_vthv_pbl_approx (l, sh, sm, dthvdz, dvdz)
              wthv(i, k, j) = Diag_wthv_pbl_approx (qsq, l, sh, dthvdz)
              wqv(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqvdz)

                ! Eq. 29 MY82
              th2v(i, k, j) = Diag_th2v_pbl_approx (l, sh, dthvdz)

                ! Eq. 26 MY82
              u2(i, k, j) = Diag_u2_pbl_approx (qsq, l, ri, dudz, dvdz, uw(i, k, j), vw(i, k, j), wthv(i, k, j))
              v2(i, k, j) = Diag_v2_pbl_approx (qsq, l, ri, dudz, dvdz, uw(i, k, j), vw(i, k, j), wthv(i, k, j))
              w2(i, k, j) = Diag_w2_pbl_approx (qsq, l, ri, dudz, dvdz, uw(i, k, j), vw(i, k, j), wthv(i, k, j))

              if (DEBUG) call Debug_negative_flux

              if (DEBUG) call Debug_big_qsq

                ! Diagnose the rest of qv fluxes
              uqv(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqvdz, uw(i, k, j), wqv(i, k, j))
              vqv(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqvdz, vw(i, k, j), wqv(i, k, j))

                ! Diagnose heat fluxes
              t_wall = T0 + fnm(k) * t(i, k, j) + fnp(k) * t(i, k - 1, j)
              qv_wall = fnm(k) * qv(i, k, j) + fnp(k) * qv(i, k - 1, j)

              uth(i, k, j) = Diag_xth_pbl_approx (t_wall, qv_wall, uthv(i, k, j), uqv(i, k, j))
              vth(i, k, j) = Diag_xth_pbl_approx (t_wall, qv_wall, vthv(i, k, j), vqv(i, k, j))
              wth(i, k, j) = Diag_xth_pbl_approx (t_wall, qv_wall, wthv(i, k, j), wqv(i, k, j))

              if ( do_scalar_mix .eq. 1 .and. ss .eq. nsteps) then
                  ! Cloud mass
                if ( p_qc .ge. param_first_scalar ) then
                  dqcdz = dqc_dz(i, k, j)
                  wqc(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqcdz)
                  uqc(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqcdz, uw(i, k, j), wqc(i, k, j))
                  vqc(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqcdz, vw(i, k, j), wqc(i, k, j))
                else
                  wqc(i, k, j) = TURB_FLUX_MIN
                  uqc(i, k, j) = TURB_FLUX_MIN
                  vqc(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Rain mass
                if ( p_qr .ge. param_first_scalar ) then
                  dqrdz = dqr_dz(i, k, j)
                  wqr(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqrdz)
                  uqr(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqrdz, uw(i, k, j), wqr(i, k, j))
                  vqr(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqrdz, vw(i, k, j), wqr(i, k, j))
                else
                  wqr(i, k, j) = TURB_FLUX_MIN
                  uqr(i, k, j) = TURB_FLUX_MIN
                  vqr(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Ice mass
                if ( p_qi .ge. param_first_scalar ) then
                  dqidz = dqi_dz(i, k, j)
                  wqi(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqidz)
                  uqi(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqidz, uw(i, k, j), wqi(i, k, j))
                  vqi(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqidz, vw(i, k, j), wqi(i, k, j))
                else
                  wqi(i, k, j) = TURB_FLUX_MIN
                  uqi(i, k, j) = TURB_FLUX_MIN
                  vqi(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Snow mass
                if ( p_qs .ge. param_first_scalar ) then
                  dqsdz = dqs_dz(i, k, j)
                  wqs(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqsdz)
                  uqs(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqsdz, uw(i, k, j), wqs(i, k, j))
                  vqs(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqsdz, vw(i, k, j), wqs(i, k, j))
                else
                  wqs(i, k, j) = TURB_FLUX_MIN
                  uqs(i, k, j) = TURB_FLUX_MIN
                  vqs(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Graupel mass
                if ( p_qg .ge. param_first_scalar ) then
                  dqgdz = dqg_dz(i, k, j)
                  wqg(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqgdz)
                  uqg(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqgdz, uw(i, k, j), wqg(i, k, j))
                  vqg(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqgdz, vw(i, k, j), wqg(i, k, j))
                else
                  wqg(i, k, j) = TURB_FLUX_MIN
                  uqg(i, k, j) = TURB_FLUX_MIN
                  vqg(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Cloud number
                if ( p_qnc .ge. param_first_scalar ) then
                  dqncdz = dqnc_dz(i, k, j)
                  wqnc(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqncdz)
                  uqnc(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqncdz, uw(i, k, j), wqnc(i, k, j))
                  vqnc(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqncdz, vw(i, k, j), wqnc(i, k, j))
                else
                  wqnc(i, k, j) = TURB_FLUX_MIN
                  uqnc(i, k, j) = TURB_FLUX_MIN
                  vqnc(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Rain number
                if ( p_qnr .ge. param_first_scalar ) then
                  dqnrdz = dqnr_dz(i, k, j)
                  wqnr(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqnrdz)
                  uqnr(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqnrdz, uw(i, k, j), wqnr(i, k, j))
                  vqnr(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqnrdz, vw(i, k, j), wqnr(i, k, j))
                else
                  wqnr(i, k, j) = TURB_FLUX_MIN
                  uqnr(i, k, j) = TURB_FLUX_MIN
                  vqnr(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Ice number
                if ( p_qni .ge. param_first_scalar ) then
                  dqnidz = dqni_dz(i, k, j)
                  wqni(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqnidz)
                  uqni(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqnidz, uw(i, k, j), wqni(i, k, j))
                  vqni(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqnidz, vw(i, k, j), wqni(i, k, j))
                else
                  wqni(i, k, j) = TURB_FLUX_MIN
                  uqni(i, k, j) = TURB_FLUX_MIN
                  vqni(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Water friendly aerosol number
                if ( p_qnwfa .ge. param_first_scalar ) then
                  dqnwfadz = dqnwfa_dz(i, k, j)
                  wqnwfa(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqnwfadz)
                  uqnwfa(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqnwfadz, uw(i, k, j), wqnwfa(i, k, j))
                  vqnwfa(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqnwfadz, vw(i, k, j), wqnwfa(i, k, j))
                else
                  wqnwfa(i, k, j) = TURB_FLUX_MIN
                  uqnwfa(i, k, j) = TURB_FLUX_MIN
                  vqnwfa(i, k, j) = TURB_FLUX_MIN
                end if
                  ! Ice friendly aerosol number
                if ( p_qnifa .ge. param_first_scalar ) then
                  dqnifadz = dqnifa_dz(i, k, j)
                  wqnifa(i, k, j) = Diag_wqv_pbl_approx (qsq, l, sh, dqnifadz)
                  uqnifa(i, k, j) = Diag_uqv_pbl_approx (qsq, l, dudz, dqnifadz, uw(i, k, j), wqnifa(i, k, j))
                  vqnifa(i, k, j) = Diag_vqv_pbl_approx (qsq, l, dvdz, dqnifadz, vw(i, k, j), wqnifa(i, k, j))
                else
                  wqnifa(i, k, j) = TURB_FLUX_MIN
                  uqnifa(i, k, j) = TURB_FLUX_MIN
                  vqnifa(i, k, j) = TURB_FLUX_MIN
                end if
              else
                  ! Cloud mas
                wqc(i, k, j) = TURB_FLUX_MIN
                uqc(i, k, j) = TURB_FLUX_MIN
                vqc(i, k, j) = TURB_FLUX_MIN
                  ! Rain mass
                wqr(i, k, j) = TURB_FLUX_MIN
                uqr(i, k, j) = TURB_FLUX_MIN
                vqr(i, k, j) = TURB_FLUX_MIN
                  ! Ice mass
                wqi(i, k, j) = TURB_FLUX_MIN
                uqi(i, k, j) = TURB_FLUX_MIN
                vqi(i, k, j) = TURB_FLUX_MIN
                  ! Snow mass
                wqs(i, k, j) = TURB_FLUX_MIN
                uqs(i, k, j) = TURB_FLUX_MIN
                vqs(i, k, j) = TURB_FLUX_MIN
                  ! Graupel mass
                wqg(i, k, j) = TURB_FLUX_MIN
                uqg(i, k, j) = TURB_FLUX_MIN
                vqg(i, k, j) = TURB_FLUX_MIN
                  ! Cloud number
                wqnc(i, k, j) = TURB_FLUX_MIN
                uqnc(i, k, j) = TURB_FLUX_MIN
                vqnc(i, k, j) = TURB_FLUX_MIN
                  ! Rain number
                wqnr(i, k, j) = TURB_FLUX_MIN
                uqnr(i, k, j) = TURB_FLUX_MIN
                vqnr(i, k, j) = TURB_FLUX_MIN
                  ! Ice number
                wqni(i, k, j) = TURB_FLUX_MIN
                uqni(i, k, j) = TURB_FLUX_MIN
                vqni(i, k, j) = TURB_FLUX_MIN
                  ! Water friendly aerosol number
                wqnwfa(i, k, j) = TURB_FLUX_MIN
                uqnwfa(i, k, j) = TURB_FLUX_MIN
                vqnwfa(i, k, j) = TURB_FLUX_MIN
                  ! Ice friendly aerosol number
                wqnifa(i, k, j) = TURB_FLUX_MIN
                uqnifa(i, k, j) = TURB_FLUX_MIN
                vqnifa(i, k, j) = TURB_FLUX_MIN
              end if

            else

              call Set_turb_flux_min

            end if if_low_q_sq

          end do i_loop
        end do k_loop
      end do j_loop

        ! Zero fluxes at the suface
      call Set_turb_flux_min_surface

        ! Zero fluxes at the top
      call Set_turb_flux_min_top

      contains

        subroutine Debug_negative_flux

          if (u2(i, k, j) < 0 .or. v2(i, k, j) < 0 .or. w2(i, k, j) < 0) then
            print *, '------------------------------------------------------'
            print *, 'NEGATIVE FLUX'
            print *, 'i, k, j = ', i, k, j
            if (u2(i, k, j) < 0) then
              print *, 'u2, qsq, u2/qsq = ', u2(i, k, j), qsq, ABS( u2(i, k, j) / qsq )
            else if (v2(i, k, j) < 0) then
              print *, 'v2, qsq, v2/qsq = ', v2(i, k, j), qsq, ABS( v2(i, k, j) / qsq )
            else if (w2(i, k, j) < 0) then
              print *, 'w2, qsq, w2/qsq = ', w2(i, k, j), qsq, ABS( w2(i, k, j) / qsq )
            end if
          end if

        end subroutine Debug_negative_flux


        subroutine Debug_big_qsq

          if (u2(i, k, j) + v2(i, k, j) + w2(i, k, j) > (1.0 + epsilon(qsq)) * qsq) then
            print *, '------------------------------------------------------'
            print *, 'BIG QSQ'
            print *, 'i, k, j = ', i, k, j
            print *, 'u2, v2, w2, sum, = ', u2(i, k, j), v2(i, k, j), w2(i, k, j), (u2(i, k, j) + v2(i, k, j) + w2(i, k, j))
            print *, 'qsq, sum/qsq = ', qsq, (u2(i, k, j) + v2(i, k, j) + w2(i, k, j)) / qsq
            u2(i, k, j) = qsq / 3.0
            v2(i, k, j) = qsq / 3.0
            w2(i, k, j) = qsq / 3.0
          end if

        end subroutine Debug_big_qsq


        subroutine Set_turb_flux_min

          u2(i, k, j) = TURB_FLUX_MIN
          v2(i, k, j) = TURB_FLUX_MIN
          w2(i, k, j) = TURB_FLUX_MIN
          uv(i, k, j) = TURB_FLUX_MIN
          uw(i, k, j) = TURB_FLUX_MIN
          vw(i, k, j) = TURB_FLUX_MIN
          uqv(i, k, j) = TURB_FLUX_MIN
          vqv(i, k, j) = TURB_FLUX_MIN
          wqv(i, k, j) = TURB_FLUX_MIN
          uqc(i, k, j) = TURB_FLUX_MIN
          vqc(i, k, j) = TURB_FLUX_MIN
          wqc(i, k, j) = TURB_FLUX_MIN
          uqr(i, k, j) = TURB_FLUX_MIN
          vqr(i, k, j) = TURB_FLUX_MIN
          wqr(i, k, j) = TURB_FLUX_MIN
          uqi(i, k, j) = TURB_FLUX_MIN
          vqi(i, k, j) = TURB_FLUX_MIN
          wqi(i, k, j) = TURB_FLUX_MIN
          uqs(i, k, j) = TURB_FLUX_MIN
          vqs(i, k, j) = TURB_FLUX_MIN
          wqs(i, k, j) = TURB_FLUX_MIN
          uqg(i, k, j) = TURB_FLUX_MIN
          vqg(i, k, j) = TURB_FLUX_MIN
          wqg(i, k, j) = TURB_FLUX_MIN
          uqnc(i, k, j) = TURB_FLUX_MIN
          vqnc(i, k, j) = TURB_FLUX_MIN
          wqnc(i, k, j) = TURB_FLUX_MIN
          uqnr(i, k, j) = TURB_FLUX_MIN
          vqnr(i, k, j) = TURB_FLUX_MIN
          wqnr(i, k, j) = TURB_FLUX_MIN
          uqni(i, k, j) = TURB_FLUX_MIN
          vqni(i, k, j) = TURB_FLUX_MIN
          wqni(i, k, j) = TURB_FLUX_MIN
          uqnwfa(i, k, j) = TURB_FLUX_MIN
          vqnwfa(i, k, j) = TURB_FLUX_MIN
          wqnwfa(i, k, j) = TURB_FLUX_MIN
          uqnifa(i, k, j) = TURB_FLUX_MIN
          vqnifa(i, k, j) = TURB_FLUX_MIN
          wqnifa(i, k, j) = TURB_FLUX_MIN
          uth(i, k, j) = TURB_FLUX_MIN
          uthv(i, k, j) = TURB_FLUX_MIN
          vth(i, k, j) = TURB_FLUX_MIN
          vthv(i, k, j) = TURB_FLUX_MIN
          wth(i, k, j) = TURB_FLUX_MIN
          wthv(i, k, j) = TURB_FLUX_MIN
          th2v(i, k, j) = TURB_FLUX_MIN

        end subroutine Set_turb_flux_min


        subroutine Set_turb_flux_min_surface

          do j = j_start, j_end
            do i = i_start, i_end
              u2(i, kts, j) = TURB_FLUX_MIN
              v2(i, kts, j) = TURB_FLUX_MIN
              w2(i, kts, j) = TURB_FLUX_MIN
              uv(i, kts, j) = TURB_FLUX_MIN
              uw(i, kts, j) = TURB_FLUX_MIN
              vw(i, kts, j) = TURB_FLUX_MIN
              uqv(i, kts, j) = TURB_FLUX_MIN
              vqv(i, kts, j) = TURB_FLUX_MIN
              wqv(i, kts, j) = TURB_FLUX_MIN
              uqc(i, kts, j) = TURB_FLUX_MIN
              vqc(i, kts, j) = TURB_FLUX_MIN
              wqc(i, kts, j) = TURB_FLUX_MIN
              uqr(i, kts, j) = TURB_FLUX_MIN
              vqr(i, kts, j) = TURB_FLUX_MIN
              wqr(i, kts, j) = TURB_FLUX_MIN
              uqi(i, kts, j) = TURB_FLUX_MIN
              vqi(i, kts, j) = TURB_FLUX_MIN
              wqi(i, kts, j) = TURB_FLUX_MIN
              uqs(i, kts, j) = TURB_FLUX_MIN
              vqs(i, kts, j) = TURB_FLUX_MIN
              wqs(i, kts, j) = TURB_FLUX_MIN
              uqg(i, kts, j) = TURB_FLUX_MIN
              vqg(i, kts, j) = TURB_FLUX_MIN
              wqg(i, kts, j) = TURB_FLUX_MIN
              uqnc(i, kts, j) = TURB_FLUX_MIN
              vqnc(i, kts, j) = TURB_FLUX_MIN
              wqnc(i, kts, j) = TURB_FLUX_MIN
              uqnr(i, kts, j) = TURB_FLUX_MIN
              vqnr(i, kts, j) = TURB_FLUX_MIN
              wqnr(i, kts, j) = TURB_FLUX_MIN
              uqni(i, kts, j) = TURB_FLUX_MIN
              vqni(i, kts, j) = TURB_FLUX_MIN
              wqni(i, kts, j) = TURB_FLUX_MIN
              uqnwfa(i, kts, j) = TURB_FLUX_MIN
              vqnwfa(i, kts, j) = TURB_FLUX_MIN
              wqnwfa(i, kts, j) = TURB_FLUX_MIN
              uqnifa(i, kts, j) = TURB_FLUX_MIN
              vqnifa(i, kts, j) = TURB_FLUX_MIN
              wqnifa(i, kts, j) = TURB_FLUX_MIN
              uth(i, kts, j) = TURB_FLUX_MIN
              uthv(i, kts, j) = TURB_FLUX_MIN
              vth(i, kts, j) = TURB_FLUX_MIN
              vthv(i, kts, j) = TURB_FLUX_MIN
              wth(i, kts, j) = TURB_FLUX_MIN
              wthv(i, kts, j) = TURB_FLUX_MIN
              th2v(i, kts, j) = TURB_FLUX_MIN
            end do
          end do

        end subroutine Set_turb_flux_min_surface

        subroutine Set_turb_flux_min_top

          do j = j_start, j_end
            do i = i_start, i_end
              u2(i, ktf + 1, j) = TURB_FLUX_MIN
              v2(i, ktf + 1, j) = TURB_FLUX_MIN
              w2(i, ktf + 1, j) = TURB_FLUX_MIN
              uv(i, ktf + 1, j) = TURB_FLUX_MIN
              uw(i, ktf + 1, j) = TURB_FLUX_MIN
              vw(i, ktf + 1, j) = TURB_FLUX_MIN
              uqv(i, ktf + 1, j) = TURB_FLUX_MIN
              vqv(i, ktf + 1, j) = TURB_FLUX_MIN
              wqv(i, ktf + 1, j) = TURB_FLUX_MIN
              uqc(i, ktf + 1, j) = TURB_FLUX_MIN
              vqc(i, ktf + 1, j) = TURB_FLUX_MIN
              wqc(i, ktf + 1, j) = TURB_FLUX_MIN
              uqr(i, ktf + 1, j) = TURB_FLUX_MIN
              vqr(i, ktf + 1, j) = TURB_FLUX_MIN
              wqr(i, ktf + 1, j) = TURB_FLUX_MIN
              uqi(i, ktf + 1, j) = TURB_FLUX_MIN
              vqi(i, ktf + 1, j) = TURB_FLUX_MIN
              wqi(i, ktf + 1, j) = TURB_FLUX_MIN
              uqs(i, ktf + 1, j) = TURB_FLUX_MIN
              vqs(i, ktf + 1, j) = TURB_FLUX_MIN
              wqs(i, ktf + 1, j) = TURB_FLUX_MIN
              uqg(i, ktf + 1, j) = TURB_FLUX_MIN
              vqg(i, ktf + 1, j) = TURB_FLUX_MIN
              wqg(i, ktf + 1, j) = TURB_FLUX_MIN
              uqnc(i, ktf + 1, j) = TURB_FLUX_MIN
              vqnc(i, ktf + 1, j) = TURB_FLUX_MIN
              wqnc(i, ktf + 1, j) = TURB_FLUX_MIN
              uqnr(i, ktf + 1, j) = TURB_FLUX_MIN
              vqnr(i, ktf + 1, j) = TURB_FLUX_MIN
              wqnr(i, ktf + 1, j) = TURB_FLUX_MIN
              uqni(i, ktf + 1, j) = TURB_FLUX_MIN
              vqni(i, ktf + 1, j) = TURB_FLUX_MIN
              wqni(i, ktf + 1, j) = TURB_FLUX_MIN
              uqnwfa(i, ktf + 1, j) = TURB_FLUX_MIN
              vqnwfa(i, ktf + 1, j) = TURB_FLUX_MIN
              wqnwfa(i, ktf + 1, j) = TURB_FLUX_MIN
              uqnifa(i, ktf + 1, j) = TURB_FLUX_MIN
              vqnifa(i, ktf + 1, j) = TURB_FLUX_MIN
              wqnifa(i, ktf + 1, j) = TURB_FLUX_MIN
              uth(i, ktf + 1, j) = TURB_FLUX_MIN
              uthv(i, ktf + 1, j) = TURB_FLUX_MIN
              vth(i, ktf + 1, j) = TURB_FLUX_MIN
              vthv(i, ktf + 1, j) = TURB_FLUX_MIN
              wth(i, ktf + 1, j) = TURB_FLUX_MIN
              wthv(i, ktf + 1, j) = TURB_FLUX_MIN
              th2v(i, ktf + 1, j) = TURB_FLUX_MIN
            end do
          end do

        end subroutine Set_turb_flux_min_top

    end subroutine Diagnose_fluxes_pbl_approx


    subroutine Diagnose_fluxes_surface (pbl3d_sfc_opt, u, v, t, rho, dz, qv, ust, hfx, qfx, rmol, &
              q_sq, l_master, u2, v2, w2, uv, uw, vw, uthv, vthv, wthv, th2v, uqv, vqv, wqv, uth, vth, wth, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                             !
        ! Purpose: Calculates the surface fluxes                      !
        !                                                             !
        ! Author: M. Eghdami & Pedro A. Jimenez & Timothy W. Juliano  !
        !                                                             !
        ! Comments: Nakanishi 2001 for 3D                             !
        !                                                             !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer, intent (in)                                        :: pbl3d_sfc_opt
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: t, qv
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: u2, v2, w2, &
          uv, uw, vw, uthv, vthv, wthv, th2v, uqv, vqv, wqv, uth, vth, wth
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u, v, rho, dz
      real, dimension (ims:ime, jms:jme),          intent (in)  :: ust, hfx, qfx, rmol
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real :: zet, pmz1, pmz2, phz
      real :: qss, prt, gamma1, kz, elv
      real :: c_p, u1, v1, wind_speed
      real, dimension (its:ite, jts:jte) :: cosa, sina, ust_sq
      ! The parameters below depend on stability functions of module_sf_mynn
      REAL, PARAMETER :: cphm_st=5.0, cphm_unst=16.0, &
                         cphh_st=5.0, cphh_unst=16.0

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)

      do j = j_start, j_end
        do i = i_start, i_end
          c_p = CP * (1.0 + 0.84 * qv(i, kts, j))
          wth(i, kts, j) = hfx(i, j) / (rho(i, kts, j) * c_p)
          wthv(i, kts, j) = hfx(i, j) / (rho(i, kts, j) * CP)
          wqv(i, kts, j) = qfx(i, j) / rho(i, kts, j)
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          u1 = 0.5 * (u(i, 1, j) + u(i + 1, 1, j))
          v1 = 0.5 * (v(i, 1, j) + v(i, 1, j + 1))
          wind_speed = Max (Sqrt ((u1 ** 2.0) + (v1 ** 2.0)), 0.01)
          ust_sq(i, j) = ust(i, j) * ust(i, j)
          cosa(i, j) = u1 / wind_speed
          sina(i, j) = v1 / wind_speed
          uw(i, kts, j) = - ust_sq(i, j) * cosa(i, j)
          vw(i, kts, j) = - ust_sq(i, j) * sina(i, j)
        end do
      end do

        ! Calculate additional surface turbulent fluxes
      if (pbl3d_sfc_opt > 0) then
         ! Prandtl number
        gamma1 = 1.0 / 3.0 - 2.0 * (a_1 / b_1)
        prt = a_1 * (gamma1 - c_1) /  (a_2 * gamma1)
        do j = j_start, j_end
          do i = i_start, i_end
            if (pbl3d_sfc_opt == 1) then
              zet  = 0.0
              pmz1 = 1.0
              pmz2 = 1.0
              phz  = prt
              elv  = 1.0 ! L/kz
            else if (pbl3d_sfc_opt == 2) then
              kz  = 0.5 * dz(i, kts, j) * KARMAN
              zet = 0.5 * dz(i, kts, j) * rmol(i, j)
              elv = 0.5 * l_master(i, kts + 1, j) / kz

               ! MYNN similarity functions (from Businger)
              if ( zet >= 0.0 ) then
                pmz1 = 1.0 + (cphm_st - 1.0) * zet ! This will always appear in the denomenator
                pmz2 = 1.0 + (cphm_st) * zet
                phz = prt + cphh_st * zet
              else
                pmz1 = 1.0 / (1.0 - cphm_unst * zet) ** 0.25 - zet
                pmz2 = 1.0 / (1.0 - cphm_unst * zet) ** 0.25
                phz = prt / sqrt(1.0 - cphh_unst * zet) ! cphh_unst does not match businger
              end if

!              pmz1 = psim(i, j) - zet ! This will always appear in the denomenator
!              pmz2 = psim(i, j)
!              phz = psih(i, j)

!              if (pmz1 .le. 0.0) then
!                write(90, *) '-----------------------------'
!                write(90, *) 'i =', i, 'j = ', j, 'k = ', k
!                write(90, *) 'kz = ', kz
!                write(90, *) 'zet = ', zet
!                write(90, *) 'elv = ', elv
!                write(90, *) 'pmz1 = ', pmz1
!                write(90, *) 'pmz1 - zet = ', pmz1 - zet
!                write(90, *) 'pmz2 = ', pmz2
!                write(90, *) 'phz = ', phz
!              end if

            end if

             ! Following equations derived from MY74
             ! Eq. 46
            qss = Max(Q_SQ_MIN, (b_1 * elv * pmz1) ** (2.0 / 3.0) * ust_sq(i, j))
            q_sq(i, kts, j) = qss

             ! Other momentum Eq. 47a, b, c, d
            u2(i, kts, j) = qss * (1.0 / 3.0 + (a_1 / b_1) * &
                (4.0 * cosa(i, j) * cosa(i, j) * pmz2 - 2.0 * sina(i, j) * sina(i, j) * pmz2 + 2.0 * zet) / pmz1)
            v2(i, kts, j) = qss * (1.0 / 3.0 + (a_1 / b_1) * &
                (-2.0 * cosa(i, j) * cosa(i, j) * pmz2 + 4.0 * sina(i, j) * sina(i, j) * pmz2 + 2.0 * zet) / pmz1)
            w2(i, kts, j) = qss * (1.0 / 3.0 + (a_1 / b_1) * &
                (-2.0 * pmz2 - 4.0 * zet) / pmz1)
            uv(i, kts, j) = qss * (a_1 / b_1) * (6.0 * sina(i, j) * cosa(i, j) * pmz2) / pmz1

             ! Heat flux Eq. 48a, b
            uth(i, kts, j) = - wth(i, kts, j) * (3.0 * a_2 / b_1 ** (1.0 / 3.0)) * &
                (elv ** (2.0 / 3.0)) * (phz + pmz2) / pmz1 ** (1.0 / 3.0) * cosa(i, j)
            vth(i, kts, j) = - wth(i, kts, j) * (3.0 * a_2 / b_1 ** (1.0 / 3.0)) * &
                (elv ** (2.0 / 3.0)) * (phz + pmz2) / pmz1 ** (1.0 / 3.0) * sina(i, j)

             ! Moisture Eq. 48a, b
            uqv(i, kts, j) = - wqv(i, kts, j) * (3.0 * a_2 / b_1 ** (1.0 / 3.0)) * &
                (elv ** (2.0 / 3.0)) * (phz + pmz2) / pmz1 ** (1.0 / 3.0) * cosa(i, j)
            vqv(i, kts, j) = - wqv(i, kts, j) * (3.0 * a_2 / b_1 ** (1.0 / 3.0)) * &
                (elv ** (2.0 / 3.0)) * (phz + pmz2) / pmz1 ** (1.0 / 3.0) * sina(i, j)

             ! Heat variance Eq. 49
            th2v(i, kts, j) = wth(i, kts, j) ** 2.0 / MAX(ust_sq(i, j), 0.001) * (elv ** (2.0 / 3.0)) * &
                (b_2 / b_1 ** (1.0 / 3.0)) * phz / pmz1 ** (1.0 / 3.0)
          end do
        end do
      end if

    end subroutine Diagnose_fluxes_surface


    pure function Diag_uw_pbl_approx (q_sq, l_master, sm, du_dz)

      implicit none

      real, intent(in) :: q_sq, l_master, sm, du_dz
      real             :: diag_uw_pbl_approx

      diag_uw_pbl_approx = - Sqrt (q_sq) * l_master * sm * du_dz

    end function Diag_uw_pbl_approx


    pure function Diag_vw_pbl_approx (q_sq, l_master, sm, dv_dz)

      implicit none

      real, intent(in) :: q_sq, l_master, sm, dv_dz
      real             :: diag_vw_pbl_approx

      diag_vw_pbl_approx = - Sqrt (q_sq) * l_master * sm * dv_dz

    end function Diag_vw_pbl_approx


    pure function Diag_uv_pbl_approx (q_sq, l_master, du_dz, dv_dz, tf_uw, tf_vw)

      implicit none

      real, intent(in) :: q_sq, l_master, du_dz, dv_dz, tf_uw, tf_vw
      real             :: diag_uv_pbl_approx

      diag_uv_pbl_approx = 3.0 * a_1 * l_master / Sqrt (q_sq) * (- tf_uw * dv_dz - tf_vw * du_dz)

    end function Diag_uv_pbl_approx


    pure function Diag_uthv_pbl_approx (l_master, sh, sm, dthetav_dz, du_dz)

      implicit none

      real, intent(in) :: l_master, sh, sm, dthetav_dz, du_dz
      real             :: diag_uthv_pbl_approx

      diag_uthv_pbl_approx = 3.0 * a_2 * l_master ** 2.0 * (sh + sm) * dthetav_dz * du_dz

    end function Diag_uthv_pbl_approx


    pure function Diag_vthv_pbl_approx (l_master, sh, sm, dthetav_dz, dv_dz)

      implicit none

      real, intent(in) :: l_master, sh, sm, dthetav_dz, dv_dz
      real             :: diag_vthv_pbl_approx

      diag_vthv_pbl_approx = 3.0 * a_2 * l_master ** 2.0 * (sh + sm) * dthetav_dz * dv_dz

    end function Diag_vthv_pbl_approx


    pure function Diag_wthv_pbl_approx (q_sq, l_master, sh, dthetav_dz)

      implicit none

      real, intent(in) :: q_sq, l_master, sh, dthetav_dz
      real             :: diag_wthv_pbl_approx

      diag_wthv_pbl_approx = - Sqrt (q_sq) * l_master * sh * dthetav_dz

    end function Diag_wthv_pbl_approx


    pure function Diag_wqv_pbl_approx (q_sq, l_master, sh, dqv_dz)

      implicit none

      real, intent(in) :: q_sq, l_master, sh, dqv_dz
      real             :: diag_wqv_pbl_approx

      diag_wqv_pbl_approx = - Sqrt (q_sq) * l_master * sh * dqv_dz

    end function Diag_wqv_pbl_approx


    pure function Diag_th2v_pbl_approx (l_master, sh, dthetav_dz)

      implicit none

      real, intent(in) :: l_master, sh, dthetav_dz
      real             :: diag_th2v_pbl_approx

      diag_th2v_pbl_approx = b_2 * l_master ** 2.0 * sh * dthetav_dz ** 2.0

    end function Diag_th2v_pbl_approx


    pure function Diag_u2_pbl_approx (q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v)

      implicit none

      real, intent(in) :: q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v
      real             :: diag_u2_pbl_approx

      diag_u2_pbl_approx = q_sq / 3.0 + 2.0 * a_1 * l_master / Sqrt (q_sq) *  &
          (- 2.0 * tf_uw * du_dz + tf_vw * dv_dz - G_OVER_TREF * tf_wtheta_v)

    end function Diag_u2_pbl_approx


    pure function Diag_v2_pbl_approx (q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v)

      implicit none

      real, intent(in) :: q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v
      real             :: diag_v2_pbl_approx

      diag_v2_pbl_approx = q_sq / 3.0 + 2.0 * a_1 * l_master / Sqrt (q_sq) *  &
          (tf_uw * du_dz - 2.0 * tf_vw * dv_dz - G_OVER_TREF * tf_wtheta_v)

    end function Diag_v2_pbl_approx


    pure function Diag_w2_pbl_approx (q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v)

      implicit none

      real, intent(in) :: q_sq, l_master, rif, du_dz, dv_dz, tf_uw, tf_vw, tf_wtheta_v
      real             :: diag_w2_pbl_approx

      diag_w2_pbl_approx = q_sq / 3.0 + 2.0 * a_1 * l_master / Sqrt (q_sq) *  &
          (tf_uw * du_dz + tf_vw * dv_dz + 2.0 * G_OVER_TREF * tf_wtheta_v)

    end function Diag_w2_pbl_approx


    pure function Diag_uqv_pbl_approx (q_sq, l_master, du_dz, dqv_dz, tf_uw, tf_wqv)

      implicit none

      real, intent(in) :: q_sq, l_master, du_dz, dqv_dz, tf_uw, tf_wqv
      real             :: diag_uqv_pbl_approx

      diag_uqv_pbl_approx = - (3.0 * a_2 * l_master / Sqrt (q_sq)) * (tf_uw * dqv_dz + tf_wqv * du_dz)

    end function Diag_uqv_pbl_approx


    pure function Diag_vqv_pbl_approx (q_sq, l_master, dv_dz, dqv_dz, tf_vw, tf_wqv)

      implicit none

      real, intent(in) :: q_sq, l_master, dv_dz, dqv_dz, tf_vw, tf_wqv
      real             :: diag_vqv_pbl_approx

      diag_vqv_pbl_approx = - (3.0 * a_2 * l_master / Sqrt (q_sq)) * (tf_vw * dqv_dz + tf_wqv * dv_dz)

    end function Diag_vqv_pbl_approx


    pure function Diag_xth_pbl_approx (t_wall, qv_wall, tf_xtheta_v, tf_xqv)

      implicit none

      real, intent(in) :: t_wall, qv_wall, tf_xtheta_v, tf_xqv
      real             :: diag_xth_pbl_approx

      diag_xth_pbl_approx = (tf_xtheta_v - P608 * t_wall * tf_xqv) / (1.0 + P608 * qv_wall)

    end function Diag_xth_pbl_approx


    subroutine Calc_sm_sh_l2_or_l2p5 (my_level, du_dz, dv_dz, dthetav_dz, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, &
              kms, kme, its, ite, jts, jte, kts, kte, sm_l2, sh_l2, sm, sh, q_sq, q_sq_hl88, q_ratio, l_master_at_mass, l_master_at_face, rif)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculates Sm and Sh for level 2 model following Yamada (1975)                !
      !                                                                                        !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                                          !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      character (len = *), intent(in)                             :: my_level
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz
      real, dimension (its:ite, kts:kte, jts:jte), intent (out)   :: sm, sh
      real, dimension (its:ite, kts:kte, jts:jte), intent (out), optional :: rif, q_ratio
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in),  optional :: q_sq
      real, dimension (its:ite, kts:kte, jts:jte), intent (in),  optional :: sm_l2, sh_l2, q_sq_hl88
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in),  optional :: l_master_at_mass
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in),  optional :: l_master_at_face
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf, k_start, n_iter_sor
      real :: ri, turb_prtl_num, gm, gh, phi1, phi2, phi3, phi4, phi5, N, D
      character (len = 256) :: wrf_err_message
      real, dimension (its:ite, kts:kte, jts:jte) :: l_master

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)
      k_start = kts + 1

      level: if (my_level == 'l2') then   ! level 2 model

        j_loop_l2: do j = j_start, j_end
          k_loop_l2: do k = k_start, ktf
            i_loop_l2: do i = i_start, i_end

              if (abs(du_dz(i, k, j)) < DWIND_DZ_MIN .and. abs(dv_dz(i, k, j)) < DWIND_DZ_MIN) then
                ri = G_OVER_TREF * dthetav_dz(i, k, j) / (2.0 * DWIND_DZ_MIN * DWIND_DZ_MIN)
              else
                ri = G_OVER_TREF * dthetav_dz(i, k, j) / (du_dz(i, k, j) ** 2.0 + dv_dz(i, k, j) ** 2.0)
              end if

                ! Eq. on page 929 Y75
              rif(i, k, j) = fac1 * (ri + fac2 - sqrt(ri * ri + fac3 * ri + fac4))
                ! NaN guard. This used to write to unit 90, which is never opened anywhere in
                ! the model: gfortran auto-creates fort.90 in the working directory, every MPI
                ! rank targets the same file name, and there is no frequency limit, so a single
                ! NaN field could fill the run directory mid-run. Routed through wrf_debug
                ! instead, which is rank tagged and level gated like every other diagnostic here.
              if (rif(i, k, j) /= rif(i, k, j)) then
                write (wrf_err_message, '(A,3I6,A,3(1X,E13.6))')            &
                    'pbl3d: NaN in rif at i,k,j =', i, k, j,                &
                    ' ; dthetav_dz, du_dz, dv_dz =',                        &
                    dthetav_dz(i, k, j), du_dz(i, k, j), dv_dz(i, k, j)
                call wrf_debug (100, wrf_err_message)
              end if

              if_turb: if (rif(i, k, j) < rif_c) then

                  ! Eq. 9a Y75
                sm(i, k, j) = cm * (rif_c - rif(i, k, j)) * (rf1 - rif(i, k, j)) / ((1.0 - rif(i, k, j)) * (rf2 - rif(i, k, j)))
                  ! Eq. 11 Y75
                turb_prtl_num = (ch2 / cm) * (rf2 - rif(i, k, j)) / (rf1 - rif(i, k, j))
                sh(i, k, j) = turb_prtl_num * sm(i, k, j)

              else

                sm(i, k, j) = TURB_FLUX_MIN
                sh(i, k, j) = TURB_FLUX_MIN

              end if if_turb

            end do i_loop_l2
          end do k_loop_l2
        end do j_loop_l2

        do j = j_start, j_end
          do i = i_start, i_end
            sm(i, kts, j) = TURB_FLUX_MIN
            sh(i, kts, j) = TURB_FLUX_MIN
            sm(i, ktf + 1, j) = TURB_FLUX_MIN
            sh(i, ktf + 1, j) = TURB_FLUX_MIN
          end do
        end do

      else if (my_level == 'l2p5') then   ! level 2.5 model

        if (PRESENT(l_master_at_mass)) then

          k_start = kts

          do j = j_start, j_end
            do k = k_start, ktf
              do i = i_start, i_end
                l_master(i, k, j) = l_master_at_mass(i, k, j)
              end do
            end do
          end do

        else if (PRESENT(l_master_at_face)) then

          k_start = kts + 1

          do j = j_start, j_end
            do k = k_start, ktf
              do i = i_start, i_end
                l_master(i, k, j) = l_master_at_face(i, k, j)
              end do
            end do
          end do

        end if

        j_loop_l2p5: do j = j_start, j_end
          k_loop_l2p5: do k = k_start, ktf
            i_loop_l2p5: do i = i_start, i_end

                  ! Realizability criteria from HL88
                if ( q_sq(i, k, j) < q_sq_hl88(i, k, j) ) then
                  q_ratio(i, k, j) = sqrt( q_sq(i, k, j) / q_sq_hl88(i, k, j) )
                  sm(i, k, j) = sm_l2(i, k, j) * q_ratio(i, k, j)
                  sh(i, k, j) = sh_l2(i, k, j) * q_ratio(i, k, j)
                else
                  q_ratio(i, k, j) = sqrt( q_sq(i, k, j) / q_sq_hl88(i, k, j) )
                    ! Eqs. 33a and 33b on page 855 MY82
                  gh = - ( (l_master(i, k, j) ** 2.0) / Max (q_sq(i, k, j), Q_SQ_MIN) ) * G_OVER_TREF * dthetav_dz(i, k, j)
                  gm = ( (l_master(i, k, j) ** 2.0) / Max (q_sq(i, k, j), Q_SQ_MIN) ) * ( Max( du_dz(i, k, j) ** 2.0 + dv_dz(i, k, j) ** 2.0, 1.0E-10 ) )

                    ! Eqs. 2.31, 2.33, 2.35 - 2.41 from HL88
                  phi1 = 1.0 - 3.0 * a_2 * b_2 * gh
                  phi2 = 1.0 - 9.0  * a_1 * a_2 * gh
                  phi3 = phi1 + 9.0 * a_2 * a_2 * gh
                  phi4 = phi1 - 12.0 * a_1 * a_2 * gh
                  phi5 = phi1 - 18.0 * a_1 * a_2 * gh
                  N = phi2 + 18.0 * c_1 * a_1 * a_1 * gm
                  D = phi2 * phi4 + 6.0 * a_1 * a_1 * phi3 * gm

                  sm(i, k, j) = a_1 * (phi3 - 3.0 * c_1 * phi4) / D
                  sh(i, k, j) = a_2 * N / D

                    ! Eqs. 3.17, 3.19, 3.20 from HL88
                  sm(i, k, j) = max ( min ( sm(i, k, j), sqrt ( 0.44 ** 2.0 / gm ) ), 0.0 )
                  sh(i, k, j) = max ( min ( sh(i, k, j), 0.76 * b_2 ), 0.0 )
                end if

            end do i_loop_l2p5
          end do k_loop_l2p5
        end do j_loop_l2p5

        do j = j_start, j_end
          do i = i_start, i_end
            if (PRESENT(l_master_at_face)) then
              sm(i, kts, j) = 0.0 !TURB_FLUX_MIN
              sh(i, kts, j) = 0.0 !TURB_FLUX_MIN
            end if
            sm(i, ktf + 1, j) = 0.0 !TURB_FLUX_MIN
            sh(i, ktf + 1, j) = 0.0 !TURB_FLUX_MIN
          end do
        end do

      end if level

    end subroutine Calc_sm_sh_l2_or_l2p5


    subroutine Calc_q_sq_l2_pbl_approx (l_master, l_dissip, du_dz, dv_dz, dthetav_dz, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, q_sq_face, q_sq_hl88, sm, rif)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculates diagnostic TKE equation (level 2) for PBL approximation            !
      !                                                                                        !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                                          !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out), optional :: q_sq_face
      real, dimension (its:ite, kts:kte, jts:jte), intent (out), optional :: q_sq_hl88
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: sm, rif
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: l_dissip
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, kts1, ktf
      real :: ri, turb_prtl_num
      real, dimension (its:ite, kts:kte, jts:jte) :: q_sq
      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      kts1 = kts + 1
      ktf = Min (kte, kde - 1)

      j_loop: do j = j_start, j_end
        k_loop: do k = kts1, ktf
          i_loop: do i = i_start, i_end

            if_turb: if (rif(i, k, j) < rif_c) then
 
                ! Level 2 balance Sm q l S^2 (1 - Rif) = q^3 / (b_1 l_dissip) solved for q^2.
                ! The two length scales are not the same one: the l on the production side is
                ! the mixing length (l_master), the l on the dissipation side is l_dissip,
                ! which is what Fill_dissip_length_scale is called to supply. They coincide
                ! for pbl3d_l_opt < 3 and differ for pbl3d_l_opt >= 3, where l_dissip is the
                ! BouLac length. This previously used l_master for both, so l_dissip was
                ! passed in and never used.
              q_sq(i, k, j) =  b_1 * l_dissip(i, k, j) * l_master(i, k, j) *  &
                  (du_dz(i, k, j) ** 2.0 + dv_dz(i, k, j) ** 2.0) *           &
                  (1.0 - rif(i, k, j)) * sm(i, k, j)

              q_sq(i, k, j) = Max (q_sq(i, k, j), Q_SQ_MIN)

              if (DEBUG) call Debug_big_qsq

            else

              q_sq(i, k, j) = Q_SQ_MIN

            end if if_turb

          end do i_loop
        end do k_loop
      end do j_loop

        ! Zero q_sq at the suface and top
      do j = j_start, j_end
        do i = i_start, i_end
          q_sq(i, kts, j) = Q_SQ_MIN
          q_sq(i, ktf + 1, j) = Q_SQ_MIN
        end do
      end do

      if (PRESENT(q_sq_face)) then

        do j = j_start, j_end
          do k = kts, ktf + 1
            do i = i_start, i_end
              q_sq_face(i, k, j) = q_sq(i, k, j)
            end do
          end do
        end do

      end if

      if (PRESENT(q_sq_hl88)) then

        do j = j_start, j_end
          do k = kts, ktf + 1
            do i = i_start, i_end
              q_sq_hl88(i, k, j) = q_sq(i, k, j)
            end do
          end do
        end do

      end if

      contains

        subroutine Debug_big_qsq

          if (q_sq(i, k, j) > 20.0) then
            print *, '-----------------------------'
            print *, 'i, k, j = ', i, k, j
            print *, 'q_sq = ', q_sq(i, k, j)
            print *, 'du_dz = ', du_dz(i, k, j)
            print *, 'dv_dz = ', dv_dz(i, k, j)
            print *, 'dthetav_dz = ', dthetav_dz(i, k, j)
            print *, 'l dissip = ', l_dissip(i, k, j)
            print *, 'Ri = ', ri
            print *, 'Ri flux = ', rif(i, k, j)
            print *, 'sm = ', sm(i, k, j)
          end if

        end subroutine Debug_big_qsq

    end subroutine Calc_q_sq_l2_pbl_approx


    subroutine Calc_q_sq_l2 (l_master, l_dissip, du_dx, dv_dy, dw_dz, du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz, &
              tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_wtv, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, sm, q_sq_face, q_sq_hl88, rif)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculates diagnostic TKE equation (level 2) for full 3D model                !
      !                                                                                        !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                                          !
      !                                                                                        !
      ! Comments: This is the self consistent counterpart of Calc_q_sq_l2_pbl_approx. The       !
      !           level 2 balance production = dissipation = q^3 / (b_1 l) is evaluated with    !
      !           the full 3D production                                                        !
      !                                                                                        !
      !             - <u_i' u_j'> dU_i/dx_j + (g / T_ref) <w' thetav'>                          !
      !                                                                                        !
      !           taken from the stress tensor the 10x10 system itself returned, rather than    !
      !           with the 1D surrogate q^2 = b_1 l^2 S^2 (1 - Rif) Sm, which knows only        !
      !           du/dz, dv/dz and dthetav/dz.                                                  !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dx, dv_dy, dw_dz, &
                                    du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: tf_u2, tf_v2, tf_w2, tf_uv, tf_uw, tf_vw, tf_wtv
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: sm
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out), optional :: q_sq_face
      real, dimension (its:ite, kts:kte, jts:jte), intent (out), optional :: q_sq_hl88
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: rif
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: l_dissip
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, kts1, ktf
      real :: q_cubed, q_sq_3d
      real, dimension (its:ite, kts:kte, jts:jte) :: q_sq
      logical, parameter :: DEBUG = .false.

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      kts1 = kts + 1
      ktf = Min (kte, kde - 1)

      j_loop: do j = j_start, j_end
        k_loop: do k = kts1, ktf
          i_loop: do i = i_start, i_end

            if_turb: if (rif(i, k, j) < rif_c) then

                ! Level 2 balance, so this expression is q^3 and not q: b_1 l carries a length,
                ! the bracket carries a production m^2 s^-3, and the product is (m s^-1)^3.
              q_cubed = b_1 * l_dissip(i, k, j) * (- tf_u2(i, k, j) * du_dx(i, k, j) - tf_v2(i, k, j) * dv_dy(i, k, j) &
                      - tf_w2(i, k, j) * dw_dz(i, k, j) - tf_uv(i, k, j) * (du_dy(i, k, j) + dv_dx(i, k, j)) &
                      - tf_uw(i, k, j) * (du_dz(i, k, j) + dw_dx(i, k, j)) &
                      - tf_vw(i, k, j) * (dv_dz(i, k, j) + dw_dy(i, k, j)) + tf_wtv(i, k, j) * G_OVER_TREF)

                ! q^2 = (q^3)^(2/3), taken in one step. The floor at zero is not cosmetic: the
                ! 3D production is a sum of nine shear terms and a buoyancy term and can go
                ! negative wherever buoyant destruction outweighs the resolved shear production,
                ! and a negative base with a real exponent evaluates to NaN.
              q_sq_3d = Max (q_cubed, 0.0) ** (2.0 / 3.0)

                ! The 3D production is only informative once the stress tensor carries something.
                ! At a cold start every flux sits at TURB_FLUX_MIN, so the production vanishes,
                ! q^2 falls to its floor, Calc_fluxes then takes the no-turbulence branch and
                ! writes the fluxes straight back to their floor: q^2 is diagnosed from the
                ! fluxes and the fluxes from q^2, with no independent source anywhere in the
                ! cycle. Falling back on the 1D local-equilibrium value where the 3D one carries
                ! no information breaks that dead lock. It is the same level 2 balance evaluated
                ! with the only gradients available before a tensor exists, and it is written to
                ! agree bit for bit with Calc_q_sq_l2_pbl_approx so that the fallback and
                ! pbl3d_qsq_opt = 0 cannot disagree.
              if (q_sq_3d > Q_SQ_MIN) then
                q_sq(i, k, j) = q_sq_3d
              else
                q_sq(i, k, j) = b_1 * l_dissip(i, k, j) * l_master(i, k, j) *  &
                    (du_dz(i, k, j) ** 2.0 + dv_dz(i, k, j) ** 2.0) *           &
                    (1.0 - rif(i, k, j)) * sm(i, k, j)
              end if

              q_sq(i, k, j) = Max (q_sq(i, k, j), Q_SQ_MIN)

              if (DEBUG) call Debug_big_qsq

            else

              q_sq(i, k, j) = Q_SQ_MIN

            end if if_turb

          end do i_loop
        end do k_loop
      end do j_loop

        ! Zero q_sq at the suface and top
      do j = j_start, j_end
        do i = i_start, i_end
          q_sq(i, kts, j) = Q_SQ_MIN
          q_sq(i, ktf + 1, j) = Q_SQ_MIN
        end do
      end do

      if (PRESENT(q_sq_face)) then

        do j = j_start, j_end
          do k = kts, ktf + 1
            do i = i_start, i_end
              q_sq_face(i, k, j) = q_sq(i, k, j)
            end do
          end do
        end do

      end if

      if (PRESENT(q_sq_hl88)) then

        do j = j_start, j_end
          do k = kts, ktf + 1
            do i = i_start, i_end
              q_sq_hl88(i, k, j) = q_sq(i, k, j)
            end do
          end do
        end do

      end if

      contains

        subroutine Debug_big_qsq

          if (q_sq(i, k, j) > 20.0) then
            print *, '-----------------------------'
            print *, 'i, k, j = ', i, k, j
            print *, 'q_sq = ', q_sq(i, k, j)
            print *, 'du_dz = ', du_dz(i, k, j)
            print *, 'dv_dz = ', dv_dz(i, k, j)
            print *, 'dthetav_dz = ', dthetav_dz(i, k, j)
            print *, 'l dissip = ', l_dissip(i, k, j)
            print *, 'q^3 (3D production x b_1 l) = ', q_cubed
            print *, 'q_sq from 3D production = ', q_sq_3d
            print *, 'Ri flux = ', rif(i, k, j)
          end if

        end subroutine Debug_big_qsq

    end subroutine Calc_q_sq_l2


    subroutine Taper_q_sq (q_sq, ids, jds, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq
      integer,                                     intent (in)    :: ids, jds, ide, jde, kde,      &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      integer :: bdy_dist, taper_dist
      real    :: taper

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            bdy_dist = min( min((i-ids),(ide-i)) , min((j-jds),(jde-j)) )
            bdy_dist = max( 1, min( bdy_dist, 5 ) )
            taper_dist = 5
            if (bdy_dist .LE. taper_dist) then
              taper = max(0., min( 1., real(bdy_dist) / real(taper_dist) ) )
              q_sq(i, k, j) = q_sq(i, k, j) * taper
            end if
          end do
        end do
      end do

    end subroutine Taper_q_sq


    subroutine Diagnose_pbl_height (thetav, q_sq, z_at_w, dz, xland, zi, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                      !
      !                  NOTES ON THE PBLH FORMULATION                       !
      !                  ADAPTED FROM MYNN PBL SCHEME                        !
      !                                                                      !
      ! The 1.5-theta-increase method defines PBL heights as the level at    !
      ! which the potential temperature first exceeds the minimum potential  !
      ! temperature within the boundary layer by 1.5 K. When applied to      !
      ! observed temperatures, this method has been shown to produce PBL-    !
      ! height estimates that are unbiased relative to profiler-based        !
      ! estimates (Nielsen-Gammon et al. 2008). However, their study did not !
      ! include LLJs. Banta and Pichugina (2008) show that a TKE-based       !
      ! threshold is a good estimate of the PBL height in LLJs. Therefore,   !
      ! a hybrid definition is implemented that uses both methods, weighting !
      ! the TKE-method more during stable conditions (PBLH < 400 m).         !
      ! A variable tke threshold (TKEeps) is used since no hard-wired        !
      ! value could be found to work best in all conditions.                 !
      !                                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: thetav, q_sq, z_at_w, dz
      real, dimension (ims:ime, jms:jme),          intent (in)    :: xland
      real, dimension (ims:ime, jms:jme),          intent (out)   :: zi
      integer,                                     intent (in)    :: ids, jds, ide, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end
      integer :: kthv, ktke
      real    :: minthv, delt_thv, tke_eps, maxqke, qtke, qtkem1, pblh_tke, wt
      real, parameter :: sbl_lim  = 200.0 ! Upper limit of stable BL height (m)
      real, parameter :: sbl_damp = 400.0 ! Transition length for blending (m)

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Find minimum thetav in the lowest 200 m AGL
      do j = j_start, j_end
        do i = i_start, i_end
          k = kts + 1
          kthv = 1
          minthv = 9.E9

          do while (z_at_w(i, k, j) .le. 200.)
            if (minthv > thetav(i, k, j)) then
              minthv = thetav(i, k, j)
              kthv = k
            end if
            k = k + 1
          end do

            ! Find thetav-based PBLH (best for daytime)
          k = kthv + 1
          if ((xland(i, j) - 1.5) .ge. 0) then
              ! Water
            delt_thv = 1.0
          else
              ! Land
            delt_thv = 1.25
          ENDIF

          zi(i, j) = 0.
          k = kthv + 1
          do k = kts + 1, kte - 1
            if (thetav(i, k, j) .ge. (minthv + delt_thv)) then
              zi(i, j) = z_at_w(i, k, j) - dz(i, k - 1, j) * &
                     Min ((thetav(i, k, j) - (minthv + delt_thv)) / Max (thetav(i, k, j) - thetav(i, k - 1, j), 1E-6), 1.0)
            end if
            if (k .eq. kte - 1) zi(i, j) = z_at_w(i, kts + 1, j)
            if (zi(i, j) .ne. 0.0) exit
          end do

            ! For stable boundary layers, use TKE method to complement the
            ! thetav-based definition (when the thetav-based PBLH is below ~0.5 km).
            ! The tanh weighting function will make the TKE-based definition negligible
            ! when the thetav-based definition is above ~1 km.
          ktke = 1
          maxqke = Max (q_sq(i, kts, j), Q_SQ_MIN)
            ! Use 5% of tke max (Kosovic and Curry, 2000; JAS)
          tke_eps = maxqke / 40.
          tke_eps = Max (tke_eps, 0.02)
          pblh_tke = 0.

          k = ktke + 1
          do k = kts + 1, kte - 1
            qtke = Max (q_sq(i, k, j) / 2., Q_SQ_MIN)
            qtkem1 = Max (q_sq(i, k - 1, j) / 2., Q_SQ_MIN)
            if (qtke .le. tke_eps) then
              pblh_tke = z_at_w(i, k, j) - dz(i, k - 1, j) * &
                           Min ((tke_eps - qtke) / Max (qtkem1 - qtke, 1E-6), 1.0)
                ! In case of near zero TKE, set PBLH = lowest level
              pblh_tke = Max (pblh_tke, z_at_w(i, kts + 1, j))
            end if
            if (k .eq. kte - 1) pblh_tke = z_at_w(i, kts + 1, j)
            if (pblh_tke .ne. 0.) exit
          end do

            ! With TKE advection turned on, the TKE-based PBLH can be very large
            ! in grid points with convective precipitation (> 8 km!),
            ! so an artificial limit is imposed to not let pblh_tke exceed the
            ! theta_v-based PBL height +/- 350 m.
            ! This has no impact on 98-99% of the domain, but is the simplest patch
            ! that adequately addresses these extremely large PBLHs.
          pblh_tke = Min (pblh_tke, zi(i, j) + 350.)
          pblh_tke = Max (pblh_tke, Max (zi(i, j) - 350., 10.))

          wt = 0.5 * Tanh ((zi(i, j) - sbl_lim) / sbl_damp) + .5
          if (maxqke <= 0.05) then
            ! Cold pool situation - default to thetav-based def
          else
            ! Blend the two PBLH types here
            zi(i, j) = pblh_tke * (1. - wt) + zi(i, j) * wt
          end if
        end do
      end do

    end subroutine Diagnose_pbl_height


    subroutine Calc_scale_aware (pbl3d_scale_aware, dx, dy, msftx, msfty, pblh, Psig_bl, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      !              NOTES ON THE SCALE-AWARE FORMULATION                        !
      !                  ADAPTED FROM MYNN PBL SCHEME                            !
      !                                                                          !
      ! JOE: add scale-aware factor (Psig) here, taken from Honnert et al.       !
      ! (2011, JAS) and/or from Hyeyum Hailey Shin and Song-You Hong (2013, JAS) !
      !                                                                          !
      ! Psig_bl tapers local mixing by adjusting magnitude of length scales      !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer,                                     intent (in)    :: pbl3d_scale_aware
      real, dimension (ims:ime, jms:jme),          intent (in)    :: pblh, msftx, msfty
      real, dimension (ims:ime, jms:jme),          intent (out)   :: Psig_bl
      real,                                        intent (in)    :: dx, dy
      integer,                                     intent (in)    :: ids, jds, ide, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end
      real :: dxdy, dxdh

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Compute Psig_bl
      Psig_bl(i_start:i_end,j_start:j_end) = 1.0

      if (pbl3d_scale_aware .gt. 0) then  ! scale-aware
        do j = j_start, j_end
          do i = i_start, i_end
            dxdy = ( dx/msftx(i,j) * dy/msfty(i,j) )**0.5
            dxdh = MAX(2.5*dxdy,10.)/MIN(pblh(i,j),3000.)

            ! Honnert et al. 2011
            ! New form to preseve parameterized mixing - only down 5% at dx = 750 m
            Psig_bl(i,j) = ((dxdh**2) + 0.106*(dxdh**0.667))/((dxdh**2) + 0.066*(dxdh**0.667) + 0.071)

            if(Psig_bl(i,j) > 1.0) Psig_bl(i,j) = 1.0
            if(Psig_bl(i,j) < 0.0) Psig_bl(i,j) = 0.0
          end do
        end do
      end if

    end subroutine Calc_scale_aware


    subroutine Make_scale_aware (Psig_bl, l_master, l_boulac, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, jms:jme),          intent (in)    :: Psig_bl
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: l_master, l_boulac
      integer,                                     intent (in)    :: ids, jds, ide, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, ktf, i_start, i_end, j_start, j_end

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)

        ! Compute Psig_bl
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            l_master(i,k,j) = l_master(i,k,j) * Psig_bl(i,j)
            l_boulac(i,k,j) = l_boulac(i,k,j) * Psig_bl(i,j)
          end do
        end do
      end do

    end subroutine Make_scale_aware


    subroutine Set_model_constants (pbl3d_constants)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Assigns values to the model constants                        !
      !                                                                       !
      ! Author: Pedro A. Jimenez                                              !
      !                                                                       !
      ! Method: 1) M73 constants                                              !
      !                                                                       !
      !         2) MY74 constants                                             !
      !                                                                       !
      !         3) MY82 constants                                             !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      character (len = *), intent(in) :: pbl3d_constants

      logical, parameter :: DEBUG = .false.

      real, parameter :: A1_M73 = 0.78, &
                         A2_M73 = 0.79, &
                         B1_M73 = 15.0, &
                         B2_M73 = 8.0,  &
                         C1_M73 = 0.056,&
                         C2_M73 = 0.0  ,&
                         C3_M73 = 0.0  ,&
                         ALPHA_M73 = 0.1, &
                         LAMBDA_M73 = 0.23

      real, parameter :: A1_MY74 = 0.78, &
                         A2_MY74 = 0.78, &
                         B1_MY74 = 15.0, &
                         B2_MY74 = 8.0,  &
                         C1_MY74 = 0.056,&
                         C2_MY74 = 0.0  ,&
                         C3_MY74 = 0.0  ,&
                         ALPHA_MY74 = 0.1, &
                         LAMBDA_MY74 = 0.23

      real, parameter :: A1_MY82 = 0.92, &
                         A2_MY82 = 0.74, &
                         B1_MY82 = 16.6, &
                         B2_MY82 = 10.1, &
                         C1_MY82 = 0.08 ,&
                         C2_MY82 = 0.0  ,&
                         C3_MY82 = 0.0  ,&
                         ALPHA_MY82 = 0.1, &
                         LAMBDA_MY82 = 0.23

      real, parameter :: A1_MYJ = 0.659888514560862645,    &
                         A2_MYJ = 0.6574209922667784586,   &
                         B1_MYJ = 11.87799326209552761,    &
                         B2_MYJ = 7.226971804046074028,    &
                         C1_MYJ = 0.000830955950095854396, &
                         C2_MYJ = 0.0,                     &
                         C3_MYJ = 0.0,                     &
                         ALPHA_MYJ = 0.3,                  &
                         LAMBDA_MYJ = 0.23

      real, parameter :: A1_Boulac = 0.3,     &
                         A2_Boulac = 0.33,    &
                         B1_Boulac = 8.4,     &
                         B2_Boulac = 6.4,     &
                         C1_Boulac = 0.08,    &
                         C2_Boulac = 0.0,     &
                         C3_Boulac = 0.0,     &
                         ALPHA_Boulac = 0.1,  &
                         LAMBDA_Boulac = 0.23

        ! Set model contants
      select case (trim(pbl3d_constants))

        case('M73')

          a_1 = A1_M73
          a_2 = A2_M73
          b_1 = B1_M73
          b_2 = B2_M73
          c_1 = C1_M73
          c_2 = C2_M73
          c_3 = C3_M73
          alpha = ALPHA_M73
          lambda = LAMBDA_M73

        case('MY74')

          a_1 = A1_MY74
          a_2 = A2_MY74
          b_1 = B1_MY74
          b_2 = B2_MY74
          c_1 = C1_MY74
          c_2 = C2_MY74
          c_3 = C3_MY74
          alpha = ALPHA_MY74
          lambda = LAMBDA_MY74

        case('MY82')

          a_1 = A1_MY82
          a_2 = A2_MY82
          b_1 = B1_MY82
          b_2 = B2_MY82
          c_1 = C1_MY82
          c_2 = C2_MY82
          c_3 = C3_MY82
          alpha = ALPHA_MY82
          lambda = LAMBDA_MY82

        case('MYJ')

          a_1 = A1_MYJ
          a_2 = A2_MYJ
          b_1 = B1_MYJ
          b_2 = B2_MYJ
          c_1 = C1_MYJ
          c_2 = C2_MYJ
          c_3 = C3_MYJ
          alpha = ALPHA_MYJ
          lambda = LAMBDA_MYJ

        case('Boulac')

          a_1 = A1_Boulac
          a_2 = A2_Boulac
          b_1 = B1_Boulac
          b_2 = B2_Boulac
          c_1 = C1_Boulac
          c_2 = C2_Boulac
          c_3 = C3_Boulac
          alpha = ALPHA_Boulac
          lambda = LAMBDA_Boulac

        case default

          write (OUTPUT_UNIT, *) 'ERROR: Unknown definition of model constants'
          write (OUTPUT_UNIT, *) 'Valid values of turbmix3d_constants are Y73, MY74 and MY82'
          stop

      end select

      if (DEBUG) then
        write (OUTPUT_UNIT, *) 'Inside subroutine Set_model_constants:'
        write (OUTPUT_UNIT, *) 'Model constants:'
        write (OUTPUT_UNIT, *) 'a1 = ', a_1
        write (OUTPUT_UNIT, *) 'a2 = ', a_2
        write (OUTPUT_UNIT, *) 'b1 = ', b_1
        write (OUTPUT_UNIT, *) 'b2 = ', b_2
        write (OUTPUT_UNIT, *) 'c1 = ', c_1
        write (OUTPUT_UNIT, *) 'c2 = ', c_2
        write (OUTPUT_UNIT, *) 'c3 = ', c_3
        write (OUTPUT_UNIT, *) 'Alpha = ', alpha
        write (OUTPUT_UNIT, *) 'Lambda = ', lambda
      end if

      if (DEBUG) print *, 'Done Set_model_constants...'

    end subroutine Set_model_constants


    subroutine Set_my_l2_global_vars

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Set global variables for Level 2                             !
      !                                                                       !
      ! Author: Pedro A. Jimenez (adapted from MYNN)                          !
      !                                                                       !
      ! Method: 1) M75 global vars                                            !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical, parameter :: DEBUG = .false.

      real              :: e1, e2, e3, e4, e5

        ! For the level 2 model (Y75)
      e1 = b_1 - 6.0 * a_1
      e2 = b_1 + 12.0 * a_1 * (1.0 - c_2) + 3.0 * b_2 * (1.0 - c_3)
      e3 = b_1 * (1.0 - 3.0 * c_1) - 6.0 * a_1
      e4 = b_1 * (1.0 - 3.0 * c_1) + 12.0 * a_1 * (1.0 - c_2) + 9.0 * a_2 * (1.0 - c_2)
      e5 = b_1 + 3.0 * a_1 * (1.0 - c_2) + 3.0 * b_2 * (1.0 - c_3)

      rif_c = e1 / e2
      rf1   = e3 / e4
      rf2   = e1 / e5
      cm    = a_1 * e2 * e4 / (b_1 * e5)
      ch2   = a_2 * e2 / b_1

      fac1 = a_2 * e5 / (2.0 * a_1 * e4)
      fac2 = a_1 * e3 / (a_2 * e5)
      fac3 = 2.0 * (a_1 / a_2) * (e3 * e5 - 2.0 * e1 * e4 ) / (e5 * e5)
      fac4 = (a_1 * e3 / (a_2 * e5) ) ** 2.0

      if (DEBUG) print *, 'Done Set_my_l2_global_vars...'

    end subroutine Set_my_l2_global_vars


    subroutine Set_my_qsq_min (pbl3d_prog)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Set minimum values for Q_SQ and TURB_FLUX                    !
      !                                                                       !
      ! Author: Timothy W. Juliano                                            !
      !                                                                       !
      ! Method: Depending on level 2 or 2.5 model                             !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer, intent(in) :: pbl3d_prog

      logical, parameter :: DEBUG = .false.

      if (pbl3d_prog == 0) then
        Q_SQ_MIN = 1.0E-5
        TURB_FLUX_MIN = 1.0E-12
      else
        Q_SQ_MIN = 1.0E-5
        TURB_FLUX_MIN = 0.0
      end if

      if (DEBUG) print *, 'Done Set_my_qsq_min...'

    end subroutine Set_my_qsq_min


    subroutine Set_init_turb_state_my (restart, pbl3d_constants,                &
              pbl3d_nsteps, pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt,  &
              pbl3d_sk_eps_max, pbl3d_n_tau_max,                                                 &
              ids, ide, jds, jde, kds, kde,                                     &
              ims, ime, jms, jme, kms, kme,                                     &
              its, ite, jts, jte, kts, kte,                                     &
              itf, jtf, ktf, i_start, i_end, j_start, j_end,                    &
              fnm, fnp, dnw, ph, phb,                                           &
              rdzw, z_at_mass, dz,                                              &
              t_2, qv, alt, u, v, ust, hfx, qfx, rmol, rho,                     &
              du_dz, dv_dz, dthetav_dz, dqv_dz,                                 &
              q_sq, q_sq_prog, q_sq_vdiff, q_sq_hdiff, q_sq_shear,              &
              q_sq_buoyancy, q_sq_dissip,                                       &
              l_master, l_master_at_mass,                                       &
              turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,           &
              turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                   &
              turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v,       &
              turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,             &
              turb_flux_uqv, turb_flux_vqv, turb_flux_wqv                       )

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Initialize turbulence state                                  !
      !                                                                       !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano (adapted from MYNN)     !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical, parameter :: DEBUG = .true.

      logical, intent(in) :: restart
      integer, intent(in) :: pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt, pbl3d_nsteps
      real,    intent(in) :: pbl3d_sk_eps_max, pbl3d_n_tau_max
      character (len = *), intent(in) :: pbl3d_constants
      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                  intent(in)  :: fnm, fnp, dnw
      real, dimension(ims:ime, jms:jme),          intent(in)  :: ust, hfx, qfx, rmol
      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: t_2, qv, &
                                                                 u, v, alt, ph, phb
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: rho
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: q_sq_prog, q_sq,     &
          q_sq_vdiff, q_sq_hdiff, q_sq_shear, q_sq_buoyancy, q_sq_dissip
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: l_master, l_master_at_mass, &
          turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,          &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                  &
          turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v,      &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,            &
          turb_flux_uqv, turb_flux_vqv, turb_flux_wqv

      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: rdzw, z_at_mass, dz
      real, dimension(its:ite, kts:kte, jts:jte), intent(in)  :: du_dz, dv_dz, &
                                                                 dthetav_dz, dqv_dz
      integer, intent(in)  :: itf, jtf, ktf, i_start, i_end, j_start, j_end

        ! Local vars
      integer :: i, j, k
      integer :: init_iter
      real, dimension (its:ite, kts:kte, jts:jte) :: sm, sh, rif

      if (DEBUG) then
        write (OUTPUT_UNIT, *) 'Inside subroutine Init_turb_mixing_3d:'
        write (OUTPUT_UNIT, *) 'PBL3D option = ', pbl3d_opt
        write (OUTPUT_UNIT, *) 'Model constants = ', trim(pbl3d_constants)
        write (OUTPUT_UNIT, *) 'PBL3D number of substeps = ', pbl3d_nsteps
      end if

      call Set_model_constants (pbl3d_constants)

      call Set_my_l2_global_vars

      call Set_my_qsq_min (pbl3d_prog)

        ! Tier 1 tolerance. Set here rather than compiled in so it can be scanned
        ! between runs; it is the binding limit on l wherever the raw S k / eps exceeds
        ! it. Guard against a nonsensical value: at or below zero Tier 1 would force
        ! l -> 0 everywhere and the closure would return isotropic turbulence at every
        ! point, which is a silent failure rather than a configuration.
      if (pbl3d_sk_eps_max > 0.0) then
        SK_EPS_MAX = pbl3d_sk_eps_max
      else
        SK_EPS_MAX = 6.0
        call wrf_message ('--- WARNING: pbl3d_sk_eps_max must be > 0; using 6.0')
      end if

        ! Buoyancy limit on l. Same reasoning as SK_EPS_MAX: a non-positive value would
        ! force l -> 0 in every stably stratified layer, which is a silent failure rather
        ! than a configuration. To switch the limit off, set a very large value.
      if (pbl3d_n_tau_max > 0.0) then
        N_TAU_MAX = pbl3d_n_tau_max
      else
        N_TAU_MAX = 0.53
        call wrf_message ('--- WARNING: pbl3d_n_tau_max must be > 0; using 0.53')
      end if

      if (restart) return

        ! Initializes thetav, TKE, L, and the turbulent fluxes
      j_loop_init: do j = jts, jtf
        i_loop_init: do i = its, itf
          q_sq(i, kts:kte, j) = Q_SQ_MIN
            ! l_master is a length, so it must not be seeded with Q_SQ_MIN, which is a TKE
            ! floor in m2 s-2. Calc_l_master_algebra overwrites it before it is first read,
            ! so this only fixes the units and keeps the seed strictly positive should that
            ! ordering ever change; the layer depth is the natural scale to fall back on.
          l_master(i, kts:kte, j) = dz(i, kts:kte, j)
          if (pbl3d_prog == 1) then
            q_sq_prog(i, kts:ktf, j) = Q_SQ_MIN
            q_sq_vdiff(i, kts:ktf, j) = 0.0
            q_sq_hdiff(i, kts:ktf, j) = 0.0
            q_sq_shear(i, kts:ktf, j) = 0.0
            q_sq_buoyancy(i, kts:ktf, j) = 0.0
            q_sq_dissip(i, kts:ktf, j) = 0.0
            l_master_at_mass(i, kts:ktf, j) = dz(i, kts:ktf, j)   ! a length, not a TKE floor
          end if
          turb_flux_u2(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_v2(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_w2(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_uv(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_uw(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_vw(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_utheta_v(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_vtheta_v(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_wtheta_v(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_theta2_v(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_utheta(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_vtheta(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_wtheta(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_uqv(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_vqv(i, kts:kte, j) = TURB_FLUX_MIN
          turb_flux_wqv(i, kts:kte, j) = TURB_FLUX_MIN
          rho(i, kts:ktf, j) = 1. / alt(i, kts:ktf, j)
        end do i_loop_init
      end do j_loop_init

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!! FOR NOW, INITIALIZE TO MIN VALS !!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!        ! Calc stability functions
!      call Calc_sm_sh_l2_or_l2p5 (my_level='l2', du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, &
!          ids=ids, ide=ide, jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
!          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, sm=sm, sh=sh, rif=rif)

!      k = 1
!      do j = j_start, j_end
!        do i = i_start, i_end
!          q_sq(i, k, j) = Max(Q_SQ_MIN, b_1 ** (2.0 / 3.0) * ust(i, j) * ust(i, j))
!        end do
!      end do

!      do init_iter = 1, 2
!          ! Calc q_sq
!        call Calc_q_sq_l2_pbl_approx (l_master=l_master, du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, ids=ids, ide=ide, &
!            jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, &
!            jts=jts, jte=jte, kts=kts, kte=kte, q_sq_face=q_sq, sm=sm, rif=rif)

!          ! Diagnose master length scale
!         call Calc_l_master_algebra (config_flags%pbl3d_l_opt, config_flags%pbl3d_l0_opt, q_sq, dz, rdzw, rmol, turb_flux_wtheta_v, dthetav_dz, l_master, &
!             ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
!      end do

!          ! Diagnose momentum, heat, moisture fluxes for pbl approx
!      call Diagnose_fluxes_pbl_approx (fnm=fnm, fnp=fnp, t=t_2, qv=qv, ust=ust, hfx=hfx, qfx=qfx, &
!          sm_tilde=sm, sh_tilde=sh, rif=rif, q_sq=q_sq, l_master=l_master, &
!          du_dz=du_dz, dv_dz=dv_dz, dthetav_dz=dthetav_dz, dqv_dz=dqv_dz, u2=turb_flux_u2, v2=turb_flux_v2, w2=turb_flux_w2, uv=turb_flux_uv, &
!          uw=turb_flux_uw, vw=turb_flux_vw, uthv=turb_flux_utheta_v, vthv=turb_flux_vtheta_v, wthv=turb_flux_wtheta_v, th2v=turb_flux_theta2_v, &
!          uqv=turb_flux_uqv, vqv=turb_flux_vqv, wqv=turb_flux_wqv, uth=turb_flux_utheta, vth=turb_flux_vtheta, wth=turb_flux_wtheta, ids=ids, ide=ide, &
!          jds=jds, jde=jde, kds=kds, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte)

!      call Diagnose_fluxes_surface (pbl3d_sfc_opt, u, v, t_2, rho, dz, qv, ust, hfx, qfx, &
!          rmol, q_sq, l_master, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, &
!          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
!          turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, &
!          turb_flux_wtheta, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

!      if (pbl3d_prog == 1) then
!        call Fill_q_sq_prog_with_q_sq (q_sq_prog, q_sq, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
!          ! Diagnose master length scale at mass points for prognostic TKE
!        call Fill_l_mass_with_l_face (l_master_at_face, l_master_at_mass, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
!      end if

      if (DEBUG) print *, 'Done Set_init_turb_state_my...'

    end subroutine Set_init_turb_state_my

  end module module_pbl3d_my
