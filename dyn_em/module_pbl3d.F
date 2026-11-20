  module module_pbl3d

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

    use module_model_constants, only: G, P608, T0, RCP, RVOVRD
    use module_state_description, only: p_qc, p_qr, p_qi, p_qs, p_qg, p_qnc, p_qnr, p_qni, p_qnwfa, p_qnifa, param_first_scalar
    use module_domain, only: domain
    use module_big_step_utilities_em, only: grid_config_rec_type
    use module_dm, only: local_communicator, mytask, ntasks, ntasks_x, ntasks_y, local_communicator_periodic
    use module_comm_dm, only: halo_em_phys_hdiff_pbl3d_sub, period_bdy_em_hdiff_pbl3d_sub
    use module_bc, only: set_physical_bc3d
    use module_pbl3d_my, only: Set_init_turb_state_my, Calc_turb_fluxes_my, THM_FLUX_OPT, PBLH_AGL_OPT
    use module_pbl3d_my, only: Q_SQ_MIN, a_2, b_1, SQ_DIFF, SFC_QSQ_BC, SQ_IMPLICIT

    implicit none

    private

    public :: Init_pbl3d, &
              Init_temp_arrays_for_substep, Update_wrf_tends_temp_state_and_zero_tends, Allocate_temp_tends, Deallocate_temp_tends, &
              Fill_l_mass_with_l_face, Calc_turb_fluxes_driver, Vertical_turb_mix, Horizontal_turb_mix, Populate_wrflux_sgs_from_pbl3d

    real, parameter :: G_OVER_TREF = G / T0

  contains

    subroutine Init_temp_arrays_for_substep (u_2, v_2, w_2, t_2, moist, rho, q_sq_2, &
              u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp, &
              ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Prepare for sub-stepping                                     !
      !              1. Save copy of state variables                          !
      !              2. Allocate temporary tendency arrays                    !
      !              3. Zero out temporary tendency arrays                    !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u_2, v_2, w_2, t_2, moist, rho, q_sq_2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp
      real, dimension (:,:,:), allocatable, intent (inout)      :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                   t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      integer,                                     intent (in)  :: ide, jde, kde,                &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte

      call Save_copy_state (u_2, v_2, w_2, t_2, moist, rho, q_sq_2, u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, &
              rho_tmp, q_sq_tmp, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Allocate_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
              t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, its, ite, jts, jte, kts, kte)

      call Zero_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
              ide, jde, kde, its, ite, jts, jte, kts, kte)

    end subroutine Init_temp_arrays_for_substep


    subroutine Save_copy_state (u_2, v_2, w_2, t_2, moist, rho, q_sq_2, u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, &
              rho_tmp, q_sq_tmp, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Save copy of state arrays for sub-stepping                   !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u_2, v_2, w_2, t_2, moist, rho, q_sq_2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp
      integer,                                     intent (in)  :: ide, jde, kde,                &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte

        ! Local
      integer :: i, j, k, i_start, i_end, j_start, j_end, k_start, k_end

        ! Calculate indexes
      i_start = its - 1
      i_end = ite + 1
      j_start = jts - 1
      j_end = jte + 1
      k_start = kts

      k_end = Min (kte, kde - 1)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            u_tmp(i,k,j) = u_2(i,k,j)
          ENDDO
        ENDDO
      ENDDO

      k_end = Min (kte, kde - 1)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            v_tmp(i,k,j) = v_2(i,k,j)
          ENDDO
        ENDDO
      ENDDO

      k_end = kte

      DO j = j_start - 1, j_end + 1
        DO k = k_start, k_end
          DO i = i_start - 1, i_end + 1
            w_tmp(i,k,j) = w_2(i,k,j)
          ENDDO
        ENDDO
      ENDDO

      k_end = Min (kte, kde - 1)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            th_tmp(i,k,j) = t_2(i,k,j)
            qv_tmp(i,k,j) = moist(i,k,j)
            rho_tmp(i,k,j) = rho(i,k,j)
            q_sq_tmp(i,k,j) = q_sq_2(i,k,j)
          ENDDO
        ENDDO
      ENDDO

    end subroutine Save_copy_state


    subroutine Allocate_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
              t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Allocate temporary tendencies for sub-stepping               !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (:,:,:), allocatable, intent (inout)     :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                  t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      integer,                              intent (in)        :: its, ite, jts, jte, kts, kte

      IF (.NOT. ALLOCATED(ru_tendf_tmp))   ALLOCATE ( ru_tendf_tmp(its:ite,kts:kte,jts:jte)   )
      IF (.NOT. ALLOCATED(rv_tendf_tmp))   ALLOCATE ( rv_tendf_tmp(its:ite,kts:kte,jts:jte)   )
      IF (.NOT. ALLOCATED(rw_tendf_tmp))   ALLOCATE ( rw_tendf_tmp(its:ite,kts:kte,jts:jte)   )
      IF (.NOT. ALLOCATED(t_tendf_tmp))    ALLOCATE ( t_tendf_tmp(its:ite,kts:kte,jts:jte)    )
      IF (.NOT. ALLOCATED(moist_tend_tmp)) ALLOCATE ( moist_tend_tmp(its:ite,kts:kte,jts:jte) )
      IF (.NOT. ALLOCATED(q_sq_tend_tmp))  ALLOCATE ( q_sq_tend_tmp(its:ite,kts:kte,jts:jte) )

    end subroutine Allocate_temp_tends


    subroutine Deallocate_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
              t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Deallocate temporary tendencies for sub-stepping             !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (:,:,:), allocatable, intent (inout)     :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                  t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      integer,                              intent (in)        :: its, ite, jts, jte, kts, kte

      IF (ALLOCATED(ru_tendf_tmp))    DEALLOCATE ( ru_tendf_tmp   )
      IF (ALLOCATED(rv_tendf_tmp))    DEALLOCATE ( rv_tendf_tmp   )
      IF (ALLOCATED(rw_tendf_tmp))    DEALLOCATE ( rw_tendf_tmp   )
      IF (ALLOCATED(t_tendf_tmp))     DEALLOCATE ( t_tendf_tmp    )
      IF (ALLOCATED(moist_tend_tmp))  DEALLOCATE ( moist_tend_tmp )
      IF (ALLOCATED(q_sq_tend_tmp))   DEALLOCATE ( q_sq_tend_tmp  )

    end subroutine Deallocate_temp_tends


    subroutine Zero_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
              t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, ide, jde, kde, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Zero out temporary tendencies for sub-stepping               !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (its:ite, kts:kte, jts:jte), intent (out)  :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                    t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      integer,                              intent (in)          :: ide, jde, kde, its, ite, jts, jte, kts, kte

        ! Local
      integer :: i, j, k, i_start, i_end, j_start, j_end, k_start, k_end

        ! Calculate indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = jte
      k_start = kts
      k_end = kte

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            ru_tendf_tmp(i,k,j) = 0.0
          ENDDO
        ENDDO
      ENDDO

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            rv_tendf_tmp(i,k,j) = 0.0
          ENDDO
        ENDDO
      ENDDO

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            rw_tendf_tmp(i,k,j) = 0.0
          ENDDO
        ENDDO
      ENDDO

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            t_tendf_tmp(i,k,j) = 0.0
            moist_tend_tmp(i,k,j) = 0.0
            q_sq_tend_tmp(i,k,j) = 0.0
          ENDDO
        ENDDO
      ENDDO

    end subroutine Zero_temp_tends


    subroutine Update_wrf_tends_temp_state_and_zero_tends (config_flags, ru_tendf, rv_tendf, rw_tendf, t_tendf, &
              moist_tend, q_sq_tend, ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
              u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp, dt, c1h, c2h, c1f, c2f, muu, muv, mut, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                          !
      ! Purpose: Update arrays for sub-stepping                                  !
      !              1. Update WRF tendencies with temporary tendencies          !
      !              2. Update temporary state arrays with temporary tendencies  !
      !              3. Zero out temporary tendency arrays                       !
      !                                                                          !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                            !
      !                                                                          !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout)  :: ru_tendf, rv_tendf, rw_tendf, t_tendf, moist_tend, q_sq_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout)  :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                      t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout)  :: u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp
      real,                                        intent (in)     :: dt
      real, dimension (kms:kme),                   intent (in)     :: c1h, c2h, c1f, c2f
      real, dimension (ims:ime, jms:jme),          intent (in)     :: muu, muv, mut
      integer,                                     intent (in)     :: ids, ide, jds, jde, kds, kde, &
                                                                      ims, ime, jms, jme, kms, kme, &
                                                                      its, ite, jts, jte, kts, kte

      call Update_wrf_tends (config_flags, ru_tendf, rv_tendf, rw_tendf, t_tendf, moist_tend, q_sq_tend, &
          ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Update_temp_state (config_flags, u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp, &
          ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
          dt, c1h, c2h, c1f, c2f, muu, muv, mut, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme,  &
          its, ite, jts, jte, kts, kte)

      call Zero_temp_tends (ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, &
          q_sq_tend_tmp, ide, jde, kde, its, ite, jts, jte, kts, kte)

    end subroutine Update_wrf_tends_temp_state_and_zero_tends


    subroutine Update_wrf_tends (config_flags, ru_tendf, rv_tendf, rw_tendf, t_tendf, moist_tend, q_sq_tend, &
              ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Update WRF tendency arrays with temporary tendencies         !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout)  :: ru_tendf, rv_tendf, rw_tendf, t_tendf, moist_tend, q_sq_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)     :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                      t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      integer,                                     intent (in)     :: ids, ide, jds, jde, kds, kde, &
                                                                      ims, ime, jms, jme, kms, kme, &
                                                                      its, ite, jts, jte, kts, kte

        ! Local
      integer :: i, j, k, i_start, i_end, j_start, j_end, k_start, k_end

        ! Calculate indexes for u
      i_start = its
      i_end = ite
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            ru_tendf(i,k,j) = ru_tendf(i,k,j) + ru_tendf_tmp(i,k,j)
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for v
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = jte
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 1, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            rv_tendf(i,k,j) = rv_tendf(i,k,j) + rv_tendf_tmp(i,k,j)
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for w
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            rw_tendf(i,k,j) = rw_tendf(i,k,j) + rw_tendf_tmp(i,k,j)
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for theta/qv
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            t_tendf(i,k,j) = t_tendf(i,k,j) + t_tendf_tmp(i,k,j)
            moist_tend(i,k,j) = moist_tend(i,k,j) + moist_tend_tmp(i,k,j)
            q_sq_tend(i,k,j) = q_sq_tend(i,k,j) + q_sq_tend_tmp(i,k,j)
          ENDDO
        ENDDO
      ENDDO

    end subroutine Update_wrf_tends


    subroutine Update_temp_state (config_flags, u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp, &
              ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp, &
              dt, c1h, c2h, c1f, c2f, muu, muv, mut, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                       !
      ! Purpose: Updates temporary state arrays for sub-stepping              !
      !                                                                       !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                         !
      !                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout)  :: u_tmp, v_tmp, w_tmp, th_tmp, qv_tmp, rho_tmp, q_sq_tmp
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)     :: ru_tendf_tmp, rv_tendf_tmp, rw_tendf_tmp, &
                                                                      t_tendf_tmp, moist_tend_tmp, q_sq_tend_tmp
      real,                                        intent (in)     :: dt
      real, dimension (kms:kme),                   intent (in)     :: c1h, c2h, c1f, c2f
      real, dimension (ims:ime, jms:jme),          intent (in)     :: muu, muv, mut 
      integer,                                     intent (in)     :: ids, ide, jds, jde, kds, kde, &
                                                                      ims, ime, jms, jme, kms, kme, &
                                                                      its, ite, jts, jte, kts, kte

        ! Local
      integer :: i, j, k, i_start, i_end, j_start, j_end, k_start, k_end

        ! Calculate indexes for u
      i_start = its
      i_end = ite
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            u_tmp(i,k,j) = u_tmp(i,k,j) + (ru_tendf_tmp(i,k,j) * (dt / (c1h(k) * muu(i,j) + c2h(k))))
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for v
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = jte
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 1, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            v_tmp(i,k,j) = v_tmp(i,k,j) + (rv_tendf_tmp(i,k,j) * (dt / (c1h(k) * muv(i,j) + c2h(k))))
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for w
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            w_tmp(i,k,j) = w_tmp(i,k,j) + (rw_tendf_tmp(i,k,j) * (dt / (c1f(k) * mut(i,j) + c2f(k))))
          ENDDO
        ENDDO
      ENDDO

        ! Calculate indexes for theta/qv
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      k_start = kts
      k_end = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

      DO j = j_start, j_end
        DO k = k_start, k_end
          DO i = i_start, i_end
            th_tmp(i,k,j) = th_tmp(i,k,j) + (t_tendf_tmp(i,k,j) * (dt / (c1h(k) * mut(i,j) + c2h(k))))
            qv_tmp(i,k,j) = qv_tmp(i,k,j) + (moist_tend_tmp(i,k,j) * (dt / (c1h(k) * mut(i,j) + c2h(k))))
            rho_tmp(i,k,j) = rho_tmp(i,k,j)
            q_sq_tmp(i,k,j) = max ( Q_SQ_MIN , q_sq_tmp(i,k,j) + (q_sq_tend_tmp(i,k,j) * (dt / (c1h(k) * mut(i,j) + c2h(k)))) )
          ENDDO
        ENDDO
      ENDDO

    end subroutine Update_temp_state


    subroutine Calc_turb_fluxes_driver (grid, config_flags, dz, z_at_mass, z_at_w, u, v, w, th, th2, qv, qc, qr, qi, qs, qg, &
              qnc, qnr, qni, qnwfa, qnifa, &
              thetav, tsk, t2, q2, psfc, rho, ust, hfx, qfx, rmol, &
              itimestep, ss, n_tracer, q_sq, q_sq_prog, q_sq_tend, &
              q_sq_vdiff_tend, q_sq_hdiff_tend, q_sq_shear_tend, q_sq_buoyancy_tend, q_sq_dissip_tend, &
              khx, khy, khz, Psig_bl, l_master, l_master_at_mass, l_boulac, turb_flux_u2, turb_flux_v2, turb_flux_w2,   &
              turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
              turb_flux_theta2_v, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv, turb_flux_uqc, turb_flux_vqc, turb_flux_wqc, &
              turb_flux_uqr, turb_flux_vqr, turb_flux_wqr, turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, &
              turb_flux_uqs, turb_flux_vqs, turb_flux_wqs, turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, &
              turb_flux_uqnc, turb_flux_vqnc, turb_flux_wqnc, turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, &
              turb_flux_uqni, turb_flux_vqni, turb_flux_wqni, turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, &
              turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa, &
              turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, turb_flux_u2_mass, turb_flux_v2_mass, &
              turb_flux_w2_mass, turb_flux_uv_mass, turb_flux_uw_mass, turb_flux_vw_mass, turb_flux_wtheta_v_mass, &
              msfux, msfuy, msfvx, msfvy, msftx, msfty, xland, pblh, dx, dy, rdx, rdy, dn, dnw, rdz, dt, id, rdzw, fnm, fnp, cf1, cf2, cf3, &
              zx, zy, mut, c1h, c2h, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, &
              ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

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

      type (domain)              , intent (in) :: grid
      type (grid_config_rec_type), intent (in) :: config_flags
      integer, intent(in) :: itimestep, id, ss, n_tracer

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: dz, z_at_mass, z_at_w, u, v, &
          w, th, th2, qv, rho, zx, zy, rdz, rdzw
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: qc, qr, qi, qs, qg, qnc, qnr, qni, qnwfa, qnifa
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq, q_sq_prog
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_vdiff_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_hdiff_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_shear_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_buoyancy_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_dissip_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: khx, khy, khz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: thetav
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: l_master, l_master_at_mass, l_boulac
      real, dimension (ims:ime, jms:jme),          intent (in)    :: msfux, msfuy, msfvx, msfvy, msftx, msfty
      real, dimension (ims:ime, jms:jme),          intent (in)    :: tsk, t2, q2, psfc, ust, hfx, qfx, rmol, xland
      real, dimension (ims:ime, jms:jme),          intent (out)   :: pblh, Psig_bl
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
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: turb_flux_u2_mass, turb_flux_v2_mass, turb_flux_w2_mass, &
                                                                     turb_flux_uv_mass, turb_flux_uw_mass, turb_flux_vw_mass, &
                                                                     turb_flux_wtheta_v_mass
      real, dimension (kms:kme),                   intent (in)    :: fnm, fnp, dn, dnw
      real,                                        intent (in)    :: dx, dy, rdx, rdy, cf1, cf2, cf3, dt
      integer,                                     intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     ips, ipe, jps, jpe, kps, kpe, &
                                                                     its, ite, jts, jte, kts, kte

        ! Local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, &
          dw_dx, dw_dy, dw_dz, dthetav_dx, dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, dqv_dz,     &
          dqc_dx, dqc_dy, dqc_dz, dqr_dx, dqr_dy, dqr_dz, dqi_dx, dqi_dy, dqi_dz, dqs_dx, dqs_dy, dqs_dz, &
          dqg_dx, dqg_dy, dqg_dz, dqnc_dx, dqnc_dy, dqnc_dz, dqnr_dx, dqnr_dy, dqnr_dz, &
          dqni_dx, dqni_dy, dqni_dz, dqnwfa_dx, dqnwfa_dy, dqnwfa_dz, dqnifa_dx, dqnifa_dy, dqnifa_dz

        ! Opt-in corrections (OPEN_ISSUES A37, A38); 0 = previous behaviour, bit for bit
      THM_FLUX_OPT = config_flags%pbl3d_thm_flux
      PBLH_AGL_OPT = config_flags%pbl3d_pblh_agl
      if (THM_FLUX_OPT > 0 .and. config_flags%use_theta_m /= 1) &
        call wrf_error_fatal ('PBL3D: pbl3d_thm_flux > 0 requires use_theta_m = 1')

        ! Calculate derivatives at the faces to prepare for fluxes
      call Calc_wind_derivatives (config_flags, u, v, w, du_dx, dv_dy, dw_dz,  &
          du_dy, dv_dx, dw_dx, du_dz, dw_dy, dv_dz,                            &
          msftx, msfty, msfux, msfuy, msfvx, msfvy,                            &
          rdx, rdy, dn, dnw, dz, rdz,                                          &
          rdzw, fnm, fnp, cf1, cf2, cf3, zx, zy,                               &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its,     &
          ite, jts, jte, kts, kte)

      call Calc_thetav (th2, qv, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, thetav)

      call Calc_mass_var_derivatives (thetav, qv,                      &
          msftx, msfty, msfux, msfuy, msfvx, msfvy, rdx, rdy,          &
          fnm, fnp, cf1, cf2, cf3, zx, zy, rdz, rdzw, dnw, dn,         &
          dthetav_dx, dthetav_dy, dthetav_dz,                          &
          dqv_dx, dqv_dy, dqv_dz,                                      &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme,  &
          its, ite, jts, jte, kts, kte)

      if ( config_flags%pbl3d_scalar_mix .eq. 1 .and. ss .eq. config_flags%pbl3d_nsteps ) then
        call Calc_scalar_var_derivatives (qc, qr, qi, qs, qg, qnc, qnr, qni, qnwfa, qnifa, msftx, msfty, msfux, msfuy, msfvx, msfvy, &
            rdx, rdy, fnm, fnp, cf1, cf2, cf3, zx, zy, rdz, rdzw, dnw, dn, dqc_dx, dqc_dy, dqc_dz, dqr_dx, dqr_dy, dqr_dz, &
            dqi_dx, dqi_dy, dqi_dz, dqs_dx, dqs_dy, dqs_dz, dqg_dx, dqg_dy, dqg_dz, dqnc_dx, dqnc_dy, dqnc_dz, &
            dqnr_dx, dqnr_dy, dqnr_dz, dqni_dx, dqni_dy, dqni_dz, dqnwfa_dx, dqnwfa_dy, dqnwfa_dz, dqnifa_dx, dqnifa_dy, dqnifa_dz, &
            ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

      call Calc_turb_fluxes_my (config_flags, dz, z_at_mass, z_at_w, u, v, w, th, th2, qv, thetav, tsk, t2, q2, psfc, rho, ust, hfx, qfx, rmol, &
          du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, dqv_dx, dqv_dy, dqv_dz, dthetav_dx, dthetav_dy, dthetav_dz, &
          dqc_dz, dqr_dz, dqi_dz, dqs_dz, dqg_dz, dqnc_dz, dqnr_dz, dqni_dz, dqnwfa_dz, dqnifa_dz, itimestep, ss, n_tracer, q_sq, q_sq_prog, &
          Psig_bl, l_master, l_master_at_mass, l_boulac, grid%l0_asym, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_uqv, &
          turb_flux_vqv, turb_flux_wqv, turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, turb_flux_uqc, turb_flux_vqc, &
          turb_flux_wqc, turb_flux_uqr, turb_flux_vqr, turb_flux_wqr, turb_flux_uqi, turb_flux_vqi, turb_flux_wqi, &
          turb_flux_uqs, turb_flux_vqs, turb_flux_wqs, turb_flux_uqg, turb_flux_vqg, turb_flux_wqg, turb_flux_uqnc, turb_flux_vqnc, &
          turb_flux_wqnc, turb_flux_uqnr, turb_flux_vqnr, turb_flux_wqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_wqni, &
          turb_flux_uqnwfa, turb_flux_vqnwfa, turb_flux_wqnwfa, turb_flux_uqnifa, turb_flux_vqnifa, turb_flux_wqnifa, &
          msfux, msfuy, msfvx, msfvy, msftx, msfty, xland, pblh, &
          grid%pbl3d_t1_ratio, grid%pbl3d_t2_steps, grid%pbl3d_t3_flags, grid%pbl3d_sk_eps, grid%pbl3d_n_tau, grid%pbl3d_cond_a, grid%pbl3d_cond_m, &
          grid%pbl3d_qv2, grid%pbl3d_p_eps, &
          dx, dy, rdx, rdy, dn, dnw, rdz, dt, id, rdzw, fnm, fnp, cf1, cf2, cf3, zx, zy, mut, c1h, c2h, ids, ide, jds, jde, kds, kde, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Calculate eddy diffusivities for tracer mixing
      if ( ss .eq. config_flags%pbl3d_nsteps .and. n_tracer .ge. param_first_scalar ) then
        call Calc_kh (du_dz, dv_dz, dthetav_dz, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, &
            l_master, q_sq, khx, khy, khz, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

        ! Predict q_sq if level 2.5 model
      if ( config_flags%pbl3d_prog .gt. 0 ) then   ! Prognostic TKE
        call Calc_q_sq_l2p5 (grid, config_flags, u, v, w, zx, zy, th2, qv, rho, thetav, tsk, t2, q2, psfc, ust, hfx, &
            du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, dthetav_dz, q_sq, q_sq_prog, q_sq_tend, &
            q_sq_vdiff_tend, q_sq_hdiff_tend, q_sq_shear_tend, q_sq_buoyancy_tend, q_sq_dissip_tend, l_master, l_master_at_mass, l_boulac, &
            turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, &
            turb_flux_u2_mass, turb_flux_v2_mass, turb_flux_w2_mass, turb_flux_uv_mass, turb_flux_uw_mass, turb_flux_vw_mass, &
            turb_flux_wtheta_v_mass, dn, dnw, fnm, fnp, msftx, msfty, msfux, msfuy, msfvx, msfvy, mut, c1h, c2h, z_at_mass, rdx, rdy, &
            rdz, rdzw, cf1, cf2, cf3, dt, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, &
            ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)
      end if

    end subroutine Calc_turb_fluxes_driver


    subroutine Calc_wind_derivatives (config_flags, u, v, w, du_dx, dv_dy, dw_dz, du_dy, dv_dx, dw_dx, &
        du_dz, dw_dy, dv_dz, msftx, msfty, msfux, msfuy, msfvx, msfvy, rdx, rdy, dn, dnw, dz, rdz, rdzw, fnm, fnp, &
        cf1, cf2, cf3, zx, zy, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                                                         !
        ! Purpose: Calculate spatial derivatives of the wind variables at the center of the faces !
        !                                                                                         !
        ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                          !
        !                                                                                         !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u, v, w, zx, zy, dz, rdz, rdzw
      real, dimension (kms:kme), intent (in)                    :: fnm, fnp, dn, dnw
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx, msfty, msfux, msfuy, msfvx, msfvy
      real,                                        intent (in)  :: rdx, rdy, cf1, cf2, cf3
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: du_dx, dv_dy, dw_dz, du_dy, dv_dx, &
                                                                   dw_dx, du_dz, dw_dy, dv_dz

        ! Local vars: u and v divided by their map factors, at u points (x derivatives) and at v points (y derivatives)
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: u_mux, v_mvx, u_muy, v_mvy

      call Calc_dvel_dz (u, 1, 0, 0, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dz)

      call Calc_dvel_dz (v, 0, 0, 1, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dz)

      call Calc_dvel_dz (w, 0, 1, 0, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dw_dz)

      call Scale_uv_by_map_factors (config_flags, u, v, msfux, msfuy, msfvx, msfvy, u_mux, v_mvx, u_muy, v_mvy, &
          ide, jds, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Calc_duv_dx (.true., u_mux, msfux, zx, rdz, dn, dnw, fnm, fnp, msftx, rdx, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dx)

      call Calc_duv_dx (.true., v_mvx, msfvx, zx, rdz, dn, dnw, fnm, fnp, msftx, rdx, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dx)

      call Calc_dw_dx (.true., w, zx, rdz, msftx, rdx, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, dw_dx)

      call Calc_duv_dy (.true., u_muy, msfuy, zy, rdz, dn, dnw, fnm, fnp, msfty, rdy, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dy)

      call Calc_duv_dy (.true., v_mvy, msfvy, zy, rdz, dn, dnw, fnm, fnp, msfty, rdy, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dy)

      call Calc_dw_dy (.true., w, zy, rdz, msfty, rdy, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, dw_dy)

    end subroutine Calc_wind_derivatives


    subroutine Calc_dvel_dz (vel, di, dk, dj, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, &
              dvel_dz)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculate du/dz, dv/dz or dw/dz at the center of the faces. The component is  !
      !          first averaged to the mass points from its two staggered neighbours (i, k, j) !
      !          and (i + di, k + dk, j + dj): (di, dk, dj) = (1, 0, 0) for u, (0, 0, 1) for v, !
      !          (0, 1, 0) for w.                                                              !
      !                                                                                        !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                         !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: vel, rdz
      integer,                                     intent (in)  :: di, dk, dj
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dvel_dz

        ! Local vars
      integer :: i, j, k
      real, dimension (its:ite, kts:kte, jts:jte) :: vel_at_mass
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Velocity component at mass points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            vel_at_mass(i, k, j) = 0.5 * (vel(i, k, j) + vel(i + di, k + dk, j + dj))
          end do
        end do
      end do

        ! Calculate derivative at the center of the faces
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            dvel_dz(i, k, j) = (vel_at_mass(i, k, j) - vel_at_mass(i, k - 1, j)) * rdz(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Surface
          dvel_dz(i, kts, j) = 0.0
            ! Top face
          dvel_dz(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_dvel_dz


    subroutine Scale_uv_by_map_factors (config_flags, u, v, msfux, msfuy, msfvx, msfvy, u_mux, v_mvx, u_muy, v_mvy, &
              ide, jds, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                      !
      ! Purpose: Scale the horizontal wind components to account for the map projection, at  !
      !          the points where Calc_duv_dx (u points) and Calc_duv_dy (v points) need them: !
      !          u / msfux and v / msfvx at u points, u / msfuy and v / msfvy at v points      !
      !                                                                                      !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                       !
      !                                                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)  :: config_flags
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u, v
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfux, msfuy, msfvx, msfvy
      integer,                                     intent (in)  :: ide, jds, jde, kde,            &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), intent (out) :: u_mux, v_mvx, u_muy, v_mvy

        ! Local vars
      integer :: i, j, k
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! At u points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end + 1
            u_mux(i, k, j) = u(i, k, j) / msfux(i, j)
            v_mvx(i, k, j) = 0.25 * (v(i, k, j) + v(i, k, j + 1) + v(i - 1, k, j) + v(i - 1, k, j + 1)) / msfvx(i, j)
          end do
        end do
      end do

        ! At v points
      do j = j_start, j_end + 1
        do k = kts, ktf
          do i = i_start, i_end
            u_muy(i, k, j) = 0.25 * (u(i, k, j) + u(i + 1, k, j) + u(i, k, j - 1) + u(i + 1, k, j - 1)) / msfuy(i, j)
              ! Because msfvy at the poles will be undefined (1./0.),
              ! we will have trouble. But we are OK since v at the
              ! poles is 0., and that takes precedence in this case
            if ((config_flags%polar) .and. ((j == jds) .or. (j == jde))) then
              v_mvy(i, k, j) = 0.0
            else
              v_mvy(i, k, j) = v(i, k, j) / msfvy(i, j)
            end if
          end do
        end do
      end do

    end subroutine Scale_uv_by_map_factors


    subroutine Calc_duv_dx (at_faces, phi_m, msf_phi, zx, rdz_out, dn, dnw, fnm, fnp, msftx, rdx, cf1, cf2, cf3, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dphi_dx)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                           !
      ! Purpose: Calculate du/dx or dv/dx at constant height, at the center of the faces          !
      !          (at_faces) or at mass points, from the component divided by its map factor at u  !
      !          points (phi_m, Scale_uv_by_map_factors); rdz_out is the inverse layer depth at   !
      !          the output points (rdz at the faces, rdzw at mass points):                       !
      !            (partial phi / partial x)|z = msftx msf_phi ( (partial phi_m / partial x)|sigma !
      !               - (partial phi_m / partial z)|sigma (partial z / partial x)|sigma )         !
      !                                                                                           !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                            !
      !                                                                                           !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical,                                     intent (in)  :: at_faces
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), intent (in) :: phi_m
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: zx, rdz_out
      real, dimension (kms:kme),                   intent (in)  :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx, msf_phi
      real,                                        intent (in)  :: rdx, cf1, cf2, cf3
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dphi_dx

        ! Local vars
      integer :: i, j, k
      real    :: dz_dx, cft1, cft2
      real, dimension (its:ite, jts:jte) :: msf_tx_phi
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: dphi_dz_dz_dx, phi_m_at_full
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktes1 = kte - 1
      ktes2 = kte - 2
      cft2 = - 0.5 * dnw(ktes1) / dn(ktes1)
      cft1 = 1.0 - cft2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Map factor at mass points multiplied by map factor at the points of the component
      do j = j_start, j_end
        do i = i_start, i_end
          msf_tx_phi(i, j) = msftx(i, j) * msf_phi(i, j)
        end do
      end do

        ! Interpolate phi_m from half levels to full levels (u points at faces)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end + 1
            phi_m_at_full(i, k, j) = fnm(k) * phi_m(i, k, j) + fnp(k) * phi_m(i, k - 1, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end + 1
            ! Surface
          phi_m_at_full(i, 1, j) =  cf1 * phi_m(i, 1, j) + cf2 * phi_m(i, 2, j) + cf3 * phi_m(i, 3, j)
            ! Top face
          phi_m_at_full(i, kte, j) =  cft1 *  phi_m(i, ktes1, j) +  cft2 * phi_m(i, ktes2, j)
        end do
      end do

      if (at_faces) then

          ! Component associated with slope in sigma surfaces (dphi_dz_dz_dx) at the center of the
          ! faces: z difference of the half-level values averaged to the face
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
                ! dz_dx = (partial z / partial x)|sigma at center of faces
              dz_dx = 0.5 * (zx(i, k, j) + zx(i + 1, k, j))
              dphi_dz_dz_dx(i, k, j) = (0.5 * (phi_m(i, k, j) + phi_m(i + 1, k, j)) - &
                  0.5 * (phi_m(i, k - 1, j) + phi_m(i + 1, k - 1, j))) * rdz_out(i, k, j) * dz_dx
            end do
          end do
        end do

          ! x difference of the full-level values
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
              dphi_dx(i, k, j) = msf_tx_phi(i, j) * ((phi_m_at_full(i + 1, k, j) - phi_m_at_full(i, k, j)) * rdx -  &
                  dphi_dz_dz_dx(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
              ! Surface
            dphi_dx(i, kts, j) = 0.0
              ! Top face
            dphi_dx(i, kte, j) = 0.0
          end do
        end do

      else

          ! Component associated with slope in sigma surfaces (dphi_dz_dz_dx) at mass points:
          ! z difference of the full-level values averaged to the mass point
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
                ! dz_dx = (partial z / partial x)|sigma at mass points
              dz_dx = 0.25 * (zx(i, k, j) + zx(i + 1, k, j) + zx(i, k + 1, j) + zx(i + 1, k + 1, j))
              dphi_dz_dz_dx(i, k, j) = (0.5 * (phi_m_at_full(i, k + 1, j) + phi_m_at_full(i + 1, k + 1, j)) - &
                  0.5 * (phi_m_at_full(i, k, j) + phi_m_at_full(i + 1, k, j))) * rdz_out(i, k, j) * dz_dx
            end do
          end do
        end do

          ! x difference of the half-level values
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              dphi_dx(i, k, j) = msf_tx_phi(i, j) * ((phi_m(i + 1, k, j) - phi_m(i, k, j)) * rdx - dphi_dz_dz_dx(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
              ! Top
            dphi_dx(i, kte, j) = 0.0
          end do
        end do

      end if

    end subroutine Calc_duv_dx


    subroutine Calc_duv_dy (at_faces, phi_m, msf_phi, zy, rdz_out, dn, dnw, fnm, fnp, msfty, rdy, cf1, cf2, cf3, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dphi_dy)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                           !
      ! Purpose: Calculate du/dy or dv/dy at constant height, at the center of the faces          !
      !          (at_faces) or at mass points, from the component divided by its map factor at v  !
      !          points (phi_m, Scale_uv_by_map_factors); the y counterpart of Calc_duv_dx;       !
      !          rdz_out as there                                                                 !
      !                                                                                           !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                            !
      !                                                                                           !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical,                                     intent (in)  :: at_faces
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), intent (in) :: phi_m
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: zy, rdz_out
      real, dimension (kms:kme),                   intent (in)  :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfty, msf_phi
      real,                                        intent (in)  :: rdy, cf1, cf2, cf3
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dphi_dy

        ! Local vars
      integer :: i, j, k
      real    :: dz_dy, cft1, cft2
      real, dimension (its:ite, jts:jte) :: msf_ty_phi
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: dphi_dz_dz_dy, phi_m_at_full
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktes1 = kte - 1
      ktes2 = kte - 2
      cft2 = - 0.5 * dnw(ktes1) / dn(ktes1)
      cft1 = 1.0 - cft2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Map factor at mass points multiplied by map factor at the points of the component
      do j = j_start, j_end
        do i = i_start, i_end
          msf_ty_phi(i, j) = msfty(i, j) * msf_phi(i, j)
        end do
      end do

        ! Interpolate phi_m from half levels to full levels (v points at faces)
      do j = j_start, j_end + 1
        do k = kts + 1, ktf
          do i = i_start, i_end
            phi_m_at_full(i, k, j) = fnm(k) * phi_m(i, k, j) + fnp(k) * phi_m(i, k - 1, j)
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do i = i_start, i_end
            ! Surface
          phi_m_at_full(i, 1, j) =  cf1 * phi_m(i, 1, j) + cf2 * phi_m(i, 2, j) + cf3 * phi_m(i, 3, j)
            ! Top face
          phi_m_at_full(i, kte, j) = cft1 * phi_m(i, ktes1, j) +  cft2 * phi_m(i, ktes2, j)
        end do
      end do

      if (at_faces) then

          ! Component associated with slope in sigma surfaces (dphi_dz_dz_dy) at the center of the
          ! faces: z difference of the half-level values averaged to the face
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
                ! dz_dy = (partial z / partial y)|sigma at center of faces
              dz_dy = 0.5 * (zy(i, k, j) + zy(i, k, j + 1))
              dphi_dz_dz_dy(i, k, j) = (0.5 * (phi_m(i, k, j) + phi_m(i, k, j + 1)) - &
                  0.5 * (phi_m(i, k - 1, j) + phi_m(i, k - 1, j + 1))) * rdz_out(i, k, j) * dz_dy
            end do
          end do
        end do

          ! y difference of the full-level values
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
              dphi_dy(i, k, j) = msf_ty_phi(i, j) * ((phi_m_at_full(i, k, j + 1) - phi_m_at_full(i, k, j)) * rdy -  &
                  dphi_dz_dz_dy(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
              ! Surface
            dphi_dy(i, kts, j) = 0.0
              ! Top face
            dphi_dy(i, kte, j) = 0.0
          end do
        end do

      else

          ! Component associated with slope in sigma surfaces (dphi_dz_dz_dy) at mass points:
          ! z difference of the full-level values averaged to the mass point
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
                ! dz_dy = (partial z / partial y)|sigma at mass points
              dz_dy = 0.25 * (zy(i, k, j) + zy(i, k, j + 1) + zy(i, k + 1, j) + zy(i, k + 1, j + 1))
              dphi_dz_dz_dy(i, k, j) = (0.5 * (phi_m_at_full(i, k + 1, j) + phi_m_at_full(i, k + 1, j + 1)) - &
                  0.5 * (phi_m_at_full(i, k, j) + phi_m_at_full(i, k, j + 1))) * rdz_out(i, k, j) * dz_dy
            end do
          end do
        end do

          ! y difference of the half-level values
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              dphi_dy(i, k, j) = msf_ty_phi(i, j) * ((phi_m(i, k, j + 1) - phi_m(i, k, j)) * rdy - dphi_dz_dz_dy(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
              ! Top
            dphi_dy(i, kte, j) = 0.0
          end do
        end do

      end if

    end subroutine Calc_duv_dy


    subroutine Calc_dw_dx (at_faces, w, zx, rdz_out, msftx, rdx, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, dw_dx)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                     !
      ! Purpose: Calculate dw/dx at constant height, at the center of the faces (at_faces)  !
      !          or at mass points; fourth-order centred x difference. rdz_out is the       !
      !          inverse layer depth at the output points (rdz at the faces, rdzw at mass points) !
      !                                                                                     !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                      !
      !                                                                                     !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical,                                     intent (in)  :: at_faces
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: w, zx, rdz_out
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx
      real,                                        intent (in)  :: rdx
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dw_dx

        ! Local vars
      integer :: i, j, k, i_offset
      real    :: dz_dx
      real, dimension (its:ite, jts:jte) :: msf_tx_tx
      real, dimension (its - 2:ite + 2, kts:kte, jts - 2:jte + 2) :: dw_dz_dz_dx, w_mtx, w_mtx_at_half
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Map factor at mass points squared
      do j = jts, jte
        do i = its, ite
          msf_tx_tx(i, j) = msftx(i, j) * msftx(i, j)
        end do
      end do

        ! Scale w component of vector to account for map projection (two extra points for the fourth-order x difference)
      i_offset = 2
      do j = j_start, j_end
        do k = kts, kte
          do i = i_start - i_offset, i_end + i_offset
            w_mtx(i, k, j) = w(i, k, j) / msftx(i, j)
          end do
        end do
      end do

        ! Average w_mtx to the mass points (half levels)
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start - i_offset, i_end + i_offset
            w_mtx_at_half(i, k, j) = 0.5 * (w_mtx(i, k, j) + w_mtx(i, k + 1, j))
          end do
        end do
      end do

      if (at_faces) then

          ! Component associated with slope in sigma surfaces (dw_dz_dz_dx) at the center of the
          ! faces: z difference of the half-level values
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
                ! dz_dx = (partial z / partial x)|sigma at center of faces
              dz_dx = 0.5 * (zx(i, k, j) + zx(i + 1, k, j))
              dw_dz_dz_dx(i, k, j) = (w_mtx_at_half(i, k, j) - w_mtx_at_half(i, k - 1, j)) * rdz_out(i, k, j) * dz_dx
            end do
          end do
        end do

          ! (partial w / partial x)|z = msf_tx_tx * (partial w_mtx / partial x)|sigma - dw_dz_dz_dx), full levels
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
              dw_dx(i, k, j) = msf_tx_tx(i, j) * (rdx * (8.0 * (w_mtx(i + 1, k, j) - w_mtx(i - 1, k, j)) - (w_mtx(i + 2, k, j) - w_mtx(i - 2, k, j)) ) / 12.0 - dw_dz_dz_dx(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
            dw_dx(i, 1, j) = 0.0
            dw_dx(i, kte, j) = 0.0
          end do
        end do

      else

          ! Component associated with slope in sigma surfaces (dw_dz_dz_dx) at mass points:
          ! z difference of the full-level values
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
                ! dz_dx = (partial z / partial x)|sigma at mass points
              dz_dx = 0.25 * (zx(i, k, j) + zx(i + 1, k, j) + zx(i, k + 1, j) + zx(i + 1, k + 1, j))
              dw_dz_dz_dx(i, k, j) = (w_mtx(i, k + 1, j) - w_mtx(i, k, j)) * rdz_out(i, k, j) * dz_dx
            end do
          end do
        end do

          ! (partial w / partial x)|z = msf_tx_tx * (partial w_mtx / partial x)|sigma - dw_dz_dz_dx), half levels
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              dw_dx(i, k, j) = msf_tx_tx(i, j) * (rdx * (8.0 * (w_mtx_at_half(i + 1, k, j) - w_mtx_at_half(i - 1, k, j)) - (w_mtx_at_half(i + 2, k, j) - w_mtx_at_half(i - 2, k, j)) ) / 12.0 - dw_dz_dz_dx(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
            dw_dx(i, kte, j) = 0.0
          end do
        end do

      end if

    end subroutine Calc_dw_dx


    subroutine Calc_dw_dy (at_faces, w, zy, rdz_out, msfty, rdy, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, dw_dy)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                     !
      ! Purpose: Calculate dw/dy at constant height, at the center of the faces (at_faces)  !
      !          or at mass points; fourth-order centred y difference. rdz_out is the       !
      !          inverse layer depth at the output points (rdz at the faces, rdzw at mass points) !
      !                                                                                     !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                      !
      !                                                                                     !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical,                                     intent (in)  :: at_faces
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: w, zy, rdz_out
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfty
      real,                                        intent (in)  :: rdy
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dw_dy

        ! Local vars
      integer :: i, j, k, j_offset
      real    :: dz_dy
      real, dimension (its:ite, jts:jte) :: msf_ty_ty
      real, dimension (its - 2:ite + 2, kts:kte, jts - 2:jte + 2) :: dw_dz_dz_dy, w_mty, w_mty_at_half
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Map factor at mass points squared
      do j = jts, jte
        do i = its, ite
          msf_ty_ty(i, j) = msfty(i, j) * msfty(i, j)
        end do
      end do

        ! Scale w component of vector to account for map projection (two extra points for the fourth-order y difference)
      j_offset = 2
      do j = j_start - j_offset, j_end + j_offset
        do k = kts, kte
          do i = i_start, i_end
            w_mty(i, k, j) = w(i, k, j) / msfty(i, j)
          end do
        end do
      end do

        ! Average w_mty to the mass points (half levels)
      do j = j_start - j_offset, j_end + j_offset
        do k = kts, ktf
          do i = i_start, i_end
            w_mty_at_half(i, k, j) = 0.5 * (w_mty(i, k, j) + w_mty(i, k + 1, j))
          end do
        end do
      end do

      if (at_faces) then

          ! Component associated with slope in sigma surfaces (dw_dz_dz_dy) at the center of the
          ! faces: z difference of the half-level values
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
                ! dz_dy = (partial z / partial y)|sigma at center of faces
              dz_dy = 0.5 * (zy(i, k, j) + zy(i, k, j + 1))
              dw_dz_dz_dy(i, k, j) = (w_mty_at_half(i, k, j) - w_mty_at_half(i, k - 1, j)) * rdz_out(i, k, j) * dz_dy
            end do
          end do
        end do

          ! (partial w / partial y)|z = msf_ty_ty * (partial w_mty / partial y)|sigma - dw_dz_dz_dy), full levels
        do j = j_start, j_end
          do k = kts + 1, ktf
            do i = i_start, i_end
              dw_dy(i, k, j) = msf_ty_ty(i, j) * (rdy * (8.0 * (w_mty(i, k, j + 1) - w_mty(i, k, j - 1)) - (w_mty(i, k, j + 2) - w_mty(i, k, j - 2)) ) / 12.0 - dw_dz_dz_dy(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
            dw_dy(i, kts, j) = 0.0
            dw_dy(i, kte, j) = 0.0
          end do
        end do

      else

          ! Component associated with slope in sigma surfaces (dw_dz_dz_dy) at mass points:
          ! z difference of the full-level values
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
                ! dz_dy = (partial z / partial y)|sigma at mass points
              dz_dy = 0.25 * (zy(i, k, j) + zy(i, k, j + 1) + zy(i, k + 1, j) + zy(i, k + 1, j + 1))
              dw_dz_dz_dy(i, k, j) = (w_mty(i, k + 1, j) - w_mty(i, k, j)) * rdz_out(i, k, j) * dz_dy
            end do
          end do
        end do

          ! (partial w / partial y)|z = msf_ty_ty * (partial w_mty / partial y)|sigma - dw_dz_dz_dy), half levels
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              dw_dy(i, k, j) = msf_ty_ty(i, j) * (rdy * (8.0 * (w_mty_at_half(i, k, j + 1) - w_mty_at_half(i, k, j - 1)) - (w_mty_at_half(i, k, j + 2) - w_mty_at_half(i, k, j - 2)) ) / 12.0 - dw_dz_dz_dy(i, k, j))
            end do
          end do
        end do

        do j = j_start, j_end
          do i = i_start, i_end
            dw_dy(i, kte, j) = 0.0
          end do
        end do

      end if

    end subroutine Calc_dw_dy


    subroutine Calc_thetav (th, qv, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, thetav)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                   !
      ! Purpose: Calculate virtual potential temperature at mass points   !
      !                                                                   !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                    !
      !                                                                   !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: th, qv
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: thetav

        ! Local vars
      integer :: i, j, k
      real :: sqv
      integer :: ktf, i_start, i_end, j_start, j_end

      ktf = Min (kte, kde - 1)

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Calculate virtual potential temperature
      do j = j_start - 1, j_end + 1
        do k = kts, ktf
          do i = i_start - 1, i_end + 1
            sqv = qv(i, k, j) / (1.0 + qv(i, k, j))
            if (THM_FLUX_OPT == 2) then
                ! Physical theta_v - T0 = theta_dry (1 + 0.608 q) - T0 with theta_dry = (T0 + th) / (1 + (Rv/Rd) qv),
                ! th = theta_m - T0 (use_theta_m = 1), written without the T0 cancellation. OPEN_ISSUES A23.2
              thetav(i, k, j) = (th(i, k, j) * (1.0 + P608 * sqv) + T0 * (P608 * sqv - RVOVRD * qv(i, k, j))) &
                  / (1.0 + RVOVRD * qv(i, k, j))
            else
              thetav(i, k, j) = th(i, k, j) * (1.0 + P608 * sqv)
            end if
          end do
        end do
      end do

    end subroutine Calc_thetav


    subroutine Calc_mass_var_derivatives (thetav, qv, msftx, msfty, msfux, msfuy, msfvx, msfvy,  &
              rdx, rdy, fnm, fnp, cf1, cf2, cf3, zx, zy, rdz, rdzw, dnw, dn, dthetav_dx,         &
              dthetav_dy, dthetav_dz, dqv_dx, dqv_dy, dqv_dz, ids, ide, jds, jde, kds, kde,      &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte                         )

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                     !
      ! Purpose: Calculate spatial derivatives of mass variables at the center of the faces !
      !                                                                                     !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                      !
      !                                                                                     !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (kms:kme),                   intent (in)  :: fnm, fnp, dn, dnw
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfux, msfuy, msfvx, msfvy, msftx, msfty
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: thetav, qv, zx, zy
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: rdz, rdzw
      real,                                        intent (in)  :: rdx, rdy, cf1, cf2, cf3
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dthetav_dx, dthetav_dy, dthetav_dz, &
                                                                   dqv_dx,     dqv_dy,     dqv_dz

        ! Calculate thetav derivatives
      call Calc_dmassvar_dx (thetav, zx, rdz, msftx, fnm, fnp, dn, dnw, rdx, cf1, cf2, cf3,  &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dthetav_dx)

      call Calc_dmassvar_dy (thetav, zy, rdz, msfty, fnm, fnp, dn, dnw, rdy, cf1, cf2, cf3,  &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dthetav_dy)

      call Calc_dmassvar_dz (thetav, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dthetav_dz)

        ! Calculate qv derivatives
      call Calc_dmassvar_dx (qv, zx, rdz, msftx, fnm, fnp, dn, dnw, rdx, cf1, cf2, cf3,  &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dqv_dx)

      call Calc_dmassvar_dy (qv, zy, rdz, msfty, fnm, fnp, dn, dnw, rdy, cf1, cf2, cf3,  &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dqv_dy)

      call Calc_dmassvar_dz (qv, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dqv_dz)

    end subroutine Calc_mass_var_derivatives


    subroutine Calc_scalar_var_derivatives (qc, qr, qi, qs, qg, qnc, qnr, qni, qnwfa, qnifa, msftx, msfty, msfux, msfuy, msfvx, msfvy, &
              rdx, rdy, fnm, fnp, cf1, cf2, cf3, zx, zy, rdz, rdzw, dnw, dn, dqc_dx, dqc_dy, dqc_dz, dqr_dx, dqr_dy, dqr_dz, &
              dqi_dx, dqi_dy, dqi_dz, dqs_dx, dqs_dy, dqs_dz, dqg_dx, dqg_dy, dqg_dz, dqnc_dx, dqnc_dy, dqnc_dz, &
              dqnr_dx, dqnr_dy, dqnr_dz, dqni_dx, dqni_dy, dqni_dz, dqnwfa_dx, dqnwfa_dy, dqnwfa_dz, dqnifa_dx, dqnifa_dy, dqnifa_dz, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                                     !
      ! Purpose: Calculate spatial derivatives of hydrometeor & scalar variables at the center of the faces !
      !                                                                                                     !
      ! Authors: Timothy W. Juliano & Pedro A. Jimenez                                                      !
      !                                                                                                     !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (kms:kme),                   intent (in)  :: fnm, fnp, dn, dnw
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfux, msfuy, msfvx, msfvy, msftx, msfty
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: zx, zy
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: qc, qr, qi, qs, qg, qnc, qnr, qni, qnwfa, qnifa
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: rdz, rdzw
      real,                                        intent (in)  :: rdx, rdy, cf1, cf2, cf3
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dqc_dx, dqc_dy, dqc_dz, &
         dqr_dx, dqr_dy, dqr_dz, dqi_dx, dqi_dy, dqi_dz, dqs_dx, dqs_dy, dqs_dz, dqg_dx, dqg_dy, dqg_dz, &
         dqnc_dx, dqnc_dy, dqnc_dz, dqnr_dx, dqnr_dy, dqnr_dz, dqni_dx, dqni_dy, dqni_dz, &
         dqnwfa_dx, dqnwfa_dy, dqnwfa_dz, dqnifa_dx, dqnifa_dy, dqnifa_dz

      call Derivatives_of (p_qc, qc, dqc_dx, dqc_dy, dqc_dz)                  ! Cloud mass
      call Derivatives_of (p_qr, qr, dqr_dx, dqr_dy, dqr_dz)                  ! Rain mass
      call Derivatives_of (p_qi, qi, dqi_dx, dqi_dy, dqi_dz)                  ! Ice mass
      call Derivatives_of (p_qs, qs, dqs_dx, dqs_dy, dqs_dz)                  ! Snow mass
      call Derivatives_of (p_qg, qg, dqg_dx, dqg_dy, dqg_dz)                  ! Graupel mass
      call Derivatives_of (p_qnc, qnc, dqnc_dx, dqnc_dy, dqnc_dz)             ! Cloud number
      call Derivatives_of (p_qnr, qnr, dqnr_dx, dqnr_dy, dqnr_dz)             ! Rain number
      call Derivatives_of (p_qni, qni, dqni_dx, dqni_dy, dqni_dz)             ! Ice number
      call Derivatives_of (p_qnwfa, qnwfa, dqnwfa_dx, dqnwfa_dy, dqnwfa_dz)   ! Water friendly aerosol number
      call Derivatives_of (p_qnifa, qnifa, dqnifa_dx, dqnifa_dy, dqnifa_dz)   ! Ice friendly aerosol number

    contains

      subroutine Derivatives_of (p_q, q, dq_dx, dq_dy, dq_dz)

          ! The three derivatives of one hydrometeor mass or number (index p_q in moist or scalar;
          ! zero when the microphysics does not carry it)

        integer,                                     intent (in)  :: p_q
        real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q
        real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dq_dx, dq_dy, dq_dz

        if ( p_q .ge. param_first_scalar ) then
          call Calc_dmassvar_dx (q, zx, rdz, msftx, fnm, fnp, dn, dnw, rdx, cf1, cf2, cf3,  &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dq_dx)

          call Calc_dmassvar_dy (q, zy, rdz, msfty, fnm, fnp, dn, dnw, rdy, cf1, cf2, cf3,  &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dq_dy)

          call Calc_dmassvar_dz (q, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dq_dz)
        else
          dq_dx(its:ite, kts:kte, jts:jte) = 0.0
          dq_dy(its:ite, kts:kte, jts:jte) = 0.0
          dq_dz(its:ite, kts:kte, jts:jte) = 0.0
        end if

      end subroutine Derivatives_of

    end subroutine Calc_scalar_var_derivatives


    subroutine Calc_dmassvar_dx (var, zx, rdz, msftx, fnm, fnp, dn, dnw, rdx, cf1, cf2, cf3,  &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dvar_dx)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Calculate partial var over partial x        !
      !                                                      !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano       !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: var, zx, rdz
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx
      real, dimension (kms:kme),                   intent (in)  :: fnm, fnp, dn, dnw
      real,                                        intent (in)  :: rdx, cf1, cf2, cf3
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dvar_dx

        ! Local vars
      integer :: i, j, k
      real :: dz_dx
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: var_at_full, dvar_dz_dz_dx
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktf = Min (kte, kde - 1)

      ktes1 = kte - 1
      ktes2 = kte - 2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Interpolate mass var from half levels to full levels (u points at faces)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end + 1
            var_at_full(i, k, j) = 0.5 * (fnm(k) * (var(i - 1, k, j) + var(i, k, j)) + &
                fnp(k) * (var(i - 1, k - 1, j) + var(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end + 1
          var_at_full(i, kts, j) = 0.5 * (cf1 * var(i, 1, j) + cf2 * var(i, 2, j) + &
              cf3 * var(i, 3, j) + cf1 * var(i - 1, 1, j) +  &
              cf2 * var(i - 1, 2, j) + cf3 * var(i - 1, 3, j))
          var_at_full(i, ktf + 1, j) = 0.5 * (var(i, ktes1, j) + (var(i, ktes1, j) - &
              var(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
              var(i - 1, ktes1, j) + (var(i - 1, ktes1, j) - &
              var(i - 1, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

        ! Calculate component associated with slope in sigma surfaces (dvar_dz_dz_dx)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
              ! dz_dx = (partial z / partial x)|sigma at center of faces
            dz_dx = 0.5 * (zx(i, k, j) + zx(i + 1, k, j))
              ! dvar_dz_dz_dx = (partial var / partial z)|sigma (dvar_dz) *
              ! (partial z / partial x)|sigma (dz_dx)
            dvar_dz_dz_dx(i, k, j) =  (var(i, k, j) - var(i, k - 1, j)) * rdz(i, k, j) * dz_dx
          end do
        end do
      end do

        ! (partial var / partial x)|z = msftx * (partial var_at_full / partial x)|sigma - dvar_dz_dz_dx)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            dvar_dx(i, k, j) = msftx(i, j) * (var_at_full(i + 1, k, j) -  var_at_full(i, k, j)) * rdx - dvar_dz_dz_dx(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          dvar_dx(i, 1, j) = 0.0
          dvar_dx(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_dmassvar_dx


    subroutine Calc_dmassvar_dy (var, zy, rdz, msfty, fnm, fnp, dn, dnw, rdy, cf1, cf2, cf3,  &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dvar_dy)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Calculate partial var over partial y        !
      !                                                      !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano       !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: var, zy, rdz
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msfty
      real, dimension (kms:kme),                   intent (in)  :: fnm, fnp, dn, dnw
      real,                                        intent (in)  :: rdy, cf1, cf2, cf3
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dvar_dy

        ! Local vars
      integer :: i, j, k
      real :: dz_dy
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: var_at_full, dvar_dz_dz_dy
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktf = Min (kte, kde - 1)

      ktes1 = kte - 1
      ktes2 = kte - 2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Interpolate mass var from half levels to full levels (v points at faces)
      do j = j_start, j_end + 1
        do k = kts + 1,   ktf
          do i = i_start, i_end
            var_at_full(i, k, j) = 0.5 * (fnm(k) * (var(i, k, j - 1) + var(i, k, j)) + &
                fnp(k) * (var(i, k - 1, j - 1) + var(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do i = i_start, i_end
          var_at_full(i, kts, j) = 0.5 * (cf1 * var(i, 1, j) + cf2 * var(i, 2, j) + &
              cf3 * var(i, 3, j) + cf1 * var(i, 1, j - 1) +  &
              cf2 * var(i, 2, j - 1) + cf3 * var(i, 3, j - 1))
          var_at_full(i, ktf + 1, j) = 0.5 * (var(i, ktes1, j) + (var(i, ktes1, j) - &
              var(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
              var(i, ktes1, j - 1) + (var(i, ktes1, j - 1) - &
              var(i, ktes2, j - 1)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

        ! Calculate component associated with slope in sigma surfaces (dvar_dz_dz_dy)
      do j = j_start, j_end + 1
        do k = kts + 1, ktf
          do i = i_start, i_end
              ! dz_dy = (partial z / partial y)|sigma at center of faces
            dz_dy = 0.5 * (zy(i, k, j) + zy(i, k, j + 1))
              ! dvar_dz_dz_dy = (partial var / partial z)|sigma (dvar_dz) *
              ! (partial z / partial y)|sigma (dz_dy)
            dvar_dz_dz_dy(i, k, j) = (var(i, k, j) - var(i, k - 1, j)) * rdz(i, k, j) * dz_dy
          end do
        end do
      end do

        ! (partial var / partial y)|z = msfty * (partial var_at_full / partial y)|sigma - dvar_dz_dz_dy)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            dvar_dy(i, k, j) = msfty(i, j) * (var_at_full(i, k, j + 1) - var_at_full(i, k, j)) * rdy - dvar_dz_dz_dy(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          dvar_dy(i, 1, j) = 0.0
          dvar_dy(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_dmassvar_dy


    subroutine Calc_dmassvar_dz (var, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dvar_dz)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Calculate partial var over partial z        !
      !                                                      !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano       !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: var, rdz
      integer,                                     intent (in)  :: ide, jde, kde,                  &
                                                                   ims, ime, jms, jme, kms, kme,   &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dvar_dz

        ! Local vars
      integer :: i, j, k
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktf = Min (kte, kde - 1)

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

        ! Interpolate mass var from half levels to full levels (center of faces)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            dvar_dz(i, k, j) = (var(i, k, j) - var(i, k - 1, j)) * rdz(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          dvar_dz(i, kts, j) = 0.0
          dvar_dz(i, ktf + 1, j) = 0.0
        end do
      end do

    end subroutine Calc_dmassvar_dz


    subroutine Calc_kh (du_dz, dv_dz, dthetav_dz, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, &
              turb_flux_vtheta_v, turb_flux_wtheta_v, l_master, q_sq, khx, khy, khz, ids, ide, &
              jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                   !
      ! Purpose: Diagnose 3D eddy diffusivities for tracer mixing         !
      !                                                                   !
      ! Author: Timothy W. Juliano                                        !
      !                                                                   !
      ! Comments: kh* are calculated at the faces                         !
      !                                                                   !
      ! References: MY82                                                  !
      !                                                                   !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: du_dz, dv_dz, dthetav_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: turb_flux_uw, turb_flux_vw, &
                                                                   turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master, q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: khx, khy, khz
      integer, intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                 ims, ime, jms, jme, kms, kme, &
                                 its, ite, jts, jte, kts, kte

        ! local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf

        ! Define dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      ktf = Min (kte, kde - 1)

      do j = j_start, j_end
        do i = i_start, i_end
          khx(i, kts, j) = 0.0
          khy(i, kts, j) = 0.0
          khz(i, kts, j) = 0.0
        end do
      end do

        ! MY82, Eqs. 28 and 31
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
              ! Khx
            if (dthetav_dz(i, k, j) == 0.0 .or. du_dz(i, k, j) == 0.0 .or. q_sq(i, k, j) == Q_SQ_MIN) then
              khx(i, k, j) = 0.0
            else
              khx(i, k, j) = Max( ( (turb_flux_utheta_v(i, k, j) / (3.0 * a_2 * l_master(i, k, j) / sqrt(q_sq(i, k, j)))) &
                            + (turb_flux_uw(i, k, j) * dthetav_dz(i, k, j)) ) / (dthetav_dz(i, k, j) * du_dz(i, k, j)), 0.0 )
            end if
              ! Khy
            if (dthetav_dz(i, k, j) == 0.0 .or. dv_dz(i, k, j) == 0.0 .or. q_sq(i, k, j) == Q_SQ_MIN) then
              khy(i, k, j) = 0.0
            else
              khy(i, k, j) = Max( ( (turb_flux_vtheta_v(i, k, j) / (3.0 * a_2 * l_master(i, k, j) / sqrt(q_sq(i, k, j)))) &
                            + (turb_flux_vw(i, k, j) * dthetav_dz(i, k, j)) ) / (dthetav_dz(i, k, j) * dv_dz(i, k, j)), 0.0 )
            end if
              ! Khz
            if (dthetav_dz(i, k, j) == 0.0 .or. q_sq(i, k, j) == Q_SQ_MIN) then
              khz(i, k, j) = 0.0
            else
              khz(i, k, j) = Max( -turb_flux_wtheta_v(i, k, j) / dthetav_dz(i, k, j), 0.0 )
            end if
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          khx(i, ktf + 1, j) = 0.0
          khy(i, ktf + 1, j) = 0.0
          khz(i, ktf + 1, j) = 0.0
        end do
      end do

    end subroutine Calc_kh


    subroutine Vertical_turb_mix (dth, du, dv, dw, dqv, dqc, dqr, dqi, dqs, dqg, dqnc, dqnr, dqni, dqnwfa, dqnifa, &
              khz, tracer, tracer_tend, pbl3d_opt, ss, config_flags, turb_flux_wtheta, turb_flux_uw, turb_flux_vw, &
              turb_flux_w2, turb_flux_wqv, turb_flux_wqc, turb_flux_wqr, turb_flux_wqi, turb_flux_wqs, turb_flux_wqg, &
              turb_flux_wqnc, turb_flux_wqnr, turb_flux_wqni, turb_flux_wqnwfa, turb_flux_wqnifa, rdz, dnw, dn, rho, &
              fnm, fnp, n_tracer, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, &
              th_in, qv_in, mut_in, c1h_in, c2h_in, dt_in)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                               !
      ! Purpose: Performs vertical turbulent mixing   !
      !                                               !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano !
      !                                               !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer, intent(in) :: pbl3d_opt
      type (grid_config_rec_type), intent(in) :: config_flags
      integer,                     intent(in) :: ss, n_tracer
      integer,                     intent(in) :: ids, ide, jds, jde, kds, kde, &
                                                 ims, ime, jms, jme, kms, kme, &
                                                 its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                   intent(in) :: dnw, dn, fnm, fnp
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdz, khz, rho, &
          turb_flux_wtheta, turb_flux_uw, turb_flux_vw, turb_flux_w2, turb_flux_wqv, &
          turb_flux_wqc, turb_flux_wqr, turb_flux_wqi, turb_flux_wqs, turb_flux_wqg, &
          turb_flux_wqnc, turb_flux_wqnr, turb_flux_wqni, turb_flux_wqnwfa, turb_flux_wqnifa
      real, dimension (its:ite, kts:kte, jts:jte), intent(out) :: dth, &
          du, dv, dw, dqv
      real, dimension (ims:ime, kms:kme, jms:jme), intent(inout) :: dqc, dqr, dqi, dqs, dqg, &
          dqnc, dqnr, dqni, dqnwfa, dqnifa
      real, dimension (ims:ime, kms:kme, jms:jme, n_tracer), intent(in) ::  tracer
      real, dimension (ims:ime, kms:kme, jms:jme, n_tracer), intent(inout) ::  tracer_tend
        ! Only used by pbl3d_scalar_implicit = 1 (OPEN_ISSUES A31)
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in), optional :: th_in, qv_in
      real, dimension (ims:ime, jms:jme),          intent(in), optional :: mut_in
      real, dimension (kms:kme),                   intent(in), optional :: c1h_in, c2h_in
      real,                                        intent(in), optional :: dt_in
      
        ! Local vars
      integer :: im
      REAL, DIMENSION (its:ite, kts:kte, jts:jte) :: hydromet_tend
      
      call Vertical_mixing_u (du, config_flags, turb_flux_uw, &
          dnw, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms,   &
          jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Vertical_mixing_v (dv, config_flags, turb_flux_vw, &
          dnw, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms,   &
          jme, kms, kme, its, ite, jts, jte, kts, kte)

      if (pbl3d_opt > 0) then
        call Vertical_mixing_w (dw, config_flags, turb_flux_w2,   &
            dn, rho, ids, ide, jds, jde, kds, kde, ims, ime, jms, &
            jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

      call Vertical_mixing_s_with_flux (dth, config_flags, turb_flux_wtheta, &
          dnw, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms,   &
          jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Vertical_mixing_s_with_flux (dqv, config_flags, turb_flux_wqv,  &
          dnw, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms, &
          jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! pbl3d_scalar_implicit = 1 (OPEN_ISSUES A31): the explicit theta and qv tendencies above are
        ! turned into backward-Euler ones. The explicit step of the closure's vertical scalar flux goes
        ! unstable (2 dt / 2 dz odd-even mode) where the effective diffusion number exceeds 0.5; the
        ! implicit step is unconditionally stable for the down-gradient part of the flux and returns the
        ! explicit tendency unchanged where that part is small. Default 0: nothing here is executed.
      if (config_flags%pbl3d_scalar_implicit == 1) then
        if (.not. (present(th_in) .and. present(qv_in) .and. present(mut_in) .and. &
                   present(c1h_in) .and. present(c2h_in) .and. present(dt_in))) &
          call wrf_error_fatal ('PBL3D: pbl3d_scalar_implicit = 1 needs th_in, qv_in, mut_in, c1h_in, c2h_in, dt_in')
        if (config_flags%pbl3d_nsteps /= 1) &
          call wrf_error_fatal ('PBL3D: pbl3d_scalar_implicit = 1 requires pbl3d_nsteps = 1')
        call Vertical_mixing_s_implicit (dth, config_flags, turb_flux_wtheta, th_in, rdz, &
            dnw, rho, fnm, fnp, mut_in, c1h_in, c2h_in, dt_in, ids, ide, jds, jde, kds, kde, &
            ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        call Vertical_mixing_s_implicit (dqv, config_flags, turb_flux_wqv, qv_in, rdz, &
            dnw, rho, fnm, fnp, mut_in, c1h_in, c2h_in, dt_in, ids, ide, jds, jde, kds, kde, &
            ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
      end if

      if ( config_flags%pbl3d_scalar_mix .eq. 1 .and. ss .eq. config_flags%pbl3d_nsteps ) then
        call Mix_hydrometeor (p_qc, turb_flux_wqc, dqc)            ! Cloud mass
        call Mix_hydrometeor (p_qr, turb_flux_wqr, dqr)            ! Rain mass
        call Mix_hydrometeor (p_qi, turb_flux_wqi, dqi)            ! Ice mass
        call Mix_hydrometeor (p_qs, turb_flux_wqs, dqs)            ! Snow mass
        call Mix_hydrometeor (p_qg, turb_flux_wqg, dqg)            ! Graupel mass
        call Mix_hydrometeor (p_qnc, turb_flux_wqnc, dqnc)         ! Cloud number
        call Mix_hydrometeor (p_qnr, turb_flux_wqnr, dqnr)         ! Rain number
        call Mix_hydrometeor (p_qni, turb_flux_wqni, dqni)         ! Ice number
        call Mix_hydrometeor (p_qnwfa, turb_flux_wqnwfa, dqnwfa)   ! Water friendly aerosol number
        call Mix_hydrometeor (p_qnifa, turb_flux_wqnifa, dqnifa)   ! Ice friendly aerosol number
      end if

      if (ss .eq. config_flags%pbl3d_nsteps .and. n_tracer .ge. param_first_scalar) then
        do im = param_first_scalar, n_tracer
          call Vertical_mixing_s (tracer_tend(ims, kms, jms, im), config_flags, tracer(ims, kms, jms, im), &
              khz, dnw, rdz, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        end do
      end if

    contains

      subroutine Mix_hydrometeor (p_q, turb_flux_wq, dq)

          ! Adds the vertical turbulent mixing of one hydrometeor mass or number (index p_q in moist
          ! or scalar; nothing when the microphysics does not carry it) to its tendency dq

        integer,                                     intent (in)    :: p_q
        real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: turb_flux_wq
        real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: dq

        if ( p_q .ge. param_first_scalar ) then
          hydromet_tend(its:ite, kts:kte, jts:jte) = 0.0
          call Vertical_mixing_s_with_flux (hydromet_tend, config_flags, turb_flux_wq,  &
              dnw, rho, fnm, fnp, ids, ide, jds, jde, kds, kde, ims, ime, jms, &
              jme, kms, kme, its, ite, jts, jte, kts, kte)
          dq(its:ite, kts:kte, jts:jte) = dq(its:ite, kts:kte, jts:jte) + &
                                          hydromet_tend(its:ite, kts:kte, jts:jte)
        end if

      end subroutine Mix_hydrometeor

    end subroutine Vertical_turb_mix


    subroutine Vertical_mixing_u (tendency, config_flags, turb_flux, dnw, rho, fnm, fnp,  & 
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                       !
      ! Purpose: Calculates tendencies of resolved variables  !
      !          at u points due to vertical turbulent        !
      !          mixing using turbulent fluxes.               !
      !                                                       !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano        !
      !                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer, intent(in ) :: ids, ide, jds, jde, kds, kde, &
                              ims, ime, jms, jme, kms, kme, &
                              its, ite, jts, jte, kts, kte
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: turb_flux, rho
      real, dimension (its:ite, kts:kte, jts:jte), intent(out) :: tendency
      real, dimension (kms:kme), intent(in) ::    dnw, fnm, fnp

        ! Local vars
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real :: rho_avg
      real, dimension(its:ite, kts:kte, jts:jte) :: turb_flux_u
      real (kind = kind(turb_flux_u)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Define some indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end = Min (ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end = Min (jde - 2, jte)

        ! Calc flux at u point in the faces
      do j = j_start, j_end
        do i = i_start, i_end
          rho_avg = 0.5 * (rho(i - 1, kts, j) + rho(i, kts, j)) 
          turb_flux_u(i, kts, j) = rho_avg * 0.5 * (turb_flux(i - 1, kts, j) + turb_flux(i, kts, j))
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf 
          do i = i_start, i_end
            rho_avg = 0.5 * (fnm(k) * (rho(i, k, j) + rho(i - 1, k, j)) + &
                fnp(k) * (rho(i, k - 1, j) + rho(i - 1, k - 1, j)))
            turb_flux_u(i, k, j) = rho_avg * 0.5 * (turb_flux(i - 1, k, j) + turb_flux(i, k, j))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          rho_avg = 0.5 * (rho(i - 1, ktf, j) + rho(i, ktf, j))
          turb_flux_u(i, ktf + 1, j) =  rho_avg * 0.5 * (turb_flux(i - 1, ktf + 1, j) + turb_flux(i, ktf + 1, j)) 
        end do
      end do

        ! Calc tendency
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tendency(i, k, j) = ( G / dnw(k) * (turb_flux_u(i, k + 1, j) - turb_flux_u(i, k, j)) ) / N_PBL3D
          end do
        end do
      end do

    end subroutine Vertical_mixing_u


    subroutine Vertical_mixing_v (tendency, config_flags, turb_flux, dnw, rho, fnm, fnp,  &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                       !
      ! Purpose: Calculates tendencies of resolved variables  !
      !          at v points due to vertical turbulent        !
      !          mixing using turbulent fluxes.               !
      !                                                       !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano        !
      !                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags
      integer, intent (in) :: ids, ide, jds, jde, kds, kde, &
                              ims, ime, jms, jme, kms, kme, &
                              its, ite, jts, jte, kts, kte
      real, dimension (ims:ime, kms:kme, jms:jme ), intent(in) :: turb_flux, rho
      real, dimension (its:ite, kts:kte, jts:jte), intent(out) ::tendency
      real, dimension (kms:kme), intent(in) :: dnw, fnm, fnp

        ! Local vars
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real :: rho_avg
      real, dimension(its:ite, kts:kte, jts:jte) :: turb_flux_v
      real (kind = kind(turb_flux_v)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Define indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end   = Min (jde - 1, jte)

        ! Calc flux at v points in the faces
      do j = j_start, j_end
        do i = i_start, i_end
          rho_avg = 0.5 * (rho(i, kts, j - 1) + rho(i, kts, j))
          turb_flux_v(i, kts, j) = rho_avg * 0.5 * (turb_flux(i, kts, j - 1) + turb_flux(i, kts, j))
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            rho_avg = 0.5 * (fnm(k) * (rho(i, k, j - 1) + rho(i, k, j)) + &
                fnp(k) * (rho(i, k - 1, j - 1) + rho(i, k - 1, j)))
            turb_flux_v(i, k, j) = rho_avg * 0.5 * (turb_flux(i, k, j - 1) + turb_flux(i, k, j))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          rho_avg = 0.5 * (rho(i, ktf, j - 1) + rho(i, ktf, j))
          turb_flux_v(i, ktf + 1, j) =  rho_avg * 0.5 * (turb_flux(i, ktf + 1, j - 1) + turb_flux(i, ktf + 1, j))
        end do
      end do

        ! Calc tendency
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tendency(i, k, j) = ( G / dnw(k) * (turb_flux_v(i, k + 1, j) - turb_flux_v(i, k, j)) ) / N_PBL3D
          end do
        end do
      end do

    end subroutine Vertical_mixing_v


    subroutine Vertical_mixing_w (tendency, config_flags, turb_flux, dn, rho,  &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                       !
        ! Purpose: Calculates vertical velocity tendencies due  !
        !          to vertical turbulent mixing                 !
        !                                                       !
        ! Author: Pedro A. Jimenez                              !
        !                                                       !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer, intent(in) :: ids, ide, jds, jde, kds, kde, ims, &
          ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte

      real, dimension (kms:kme), intent(in) :: dn
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: turb_flux, rho
      real, dimension (its:ite, kts:kte, jts:jte), intent(out) :: tendency

        ! Local vars
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real, dimension(its:ite, kts:kte, jts:jte) :: turb_flux_mass
      real (kind = kind(turb_flux_mass)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Define some dimensions
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end = Min (jde - 2, jte)

        ! Calc flux at mass points
      do j = j_start, j_end
        do k = kts + 1, ktf - 1
          do i = i_start, i_end
            turb_flux_mass(i, k, j) = 0.5 * (turb_flux(i, k + 1, j) + turb_flux(i, k, j)) * rho(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
          do i = i_start, i_end
            turb_flux_mass(i, kts, j) = 0.5 * (turb_flux(i, kts, j) + turb_flux(i, kts + 1, j)) * rho(i, kts, j)
            turb_flux_mass(i, ktf, j) = 0.5 * (turb_flux(i, ktf, j) + turb_flux(i, ktf + 1, j)) * rho(i, ktf, j)
          end do
      end do

        ! Calc tendency
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            tendency(i, k, j) = ( G * (turb_flux_mass(i, k, j) - turb_flux_mass(i, k - 1, j)) / dn(k) ) / N_PBL3D
          end do
        end do
      end do

    end subroutine Vertical_mixing_w


    subroutine Vertical_mixing_s (tendency, config_flags, var, khz, dnw, rdz, rho, fnm, fnp,  &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                       !
        ! Purpose: Calculates tendencies of resolved variables  !
        !          at mass points due to vertical turbulent     !
        !          mixing using turbulent fluxes.               !
        !          Code adapted from module_diffusion_em.F      !
        !                                                       !
        ! Authors: Timothy W. Juliano & Pedro A. Jimenez        !
        !                                                       !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer,                     intent(in) :: ids, ide, jds, jde, kds, kde, &
                                                 ims, ime, jms, jme, kms, kme, &
                                                 its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                   intent(in) :: dnw, fnm, fnp
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: var, khz, rdz, rho
      real, dimension (ims:ime, kms:kme, jms:jme), intent(inout) :: tendency

        ! Local vars
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real, dimension(its:ite, kts:kte, jts:jte) :: H3, khz_avg

        ! Define some dimensions
      i_start = its
      i_end   = Min (ite, ide - 1)
      j_start = jts
      j_end   = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            khz_avg(i, k, j) = khz(i, k, j) * (fnm(k) * rho(i, k, j) + fnp(k) * rho(i, k - 1, j))
            H3(i, k, j) = -khz_avg(i, k, j) * (var(i, k, j) - var(i, k - 1, j)) * rdz(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          H3(i, kts, j) = 0.
          H3(i, ktf + 1, j) = 0.
        end do
      end do

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tendency(i, k, j) = tendency(i, k, j) + ( G * (H3(i, k + 1, j) - H3(i, k, j)) / dnw(k) )
          end do
        end do
      end do

    end subroutine Vertical_mixing_s


    subroutine Vertical_mixing_s_with_flux (tendency, config_flags, turb_flux, dnw, rho, fnm, fnp,  &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                       !
        ! Purpose: Calculates tendencies of resolved variables  !
        !          at mass points due to vertical turbulent     !
        !          mixing using turbulent fluxes.               !
        !                                                       !
        ! Authors: Pedro A. Jimenez & Timothy W. Juliano        !
        !                                                       !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer,                     intent(in) :: ids, ide, jds, jde, kds, kde, &
                                                 ims, ime, jms, jme, kms, kme, &
                                                 its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                   intent(in) :: dnw, fnm, fnp
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: turb_flux, rho
      real, dimension (its:ite, kts:kte, jts:jte), intent(out) :: tendency

        ! Local vars
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real :: rho_kp1, rho_k
      real (kind = kind(turb_flux)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Define some dimensions
      i_start = its
      i_end   = Min (ite, ide - 1)
      j_start = jts
      j_end   = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

        ! First layer
      do j = j_start, j_end
        do i = i_start, i_end
          rho_k = rho(i, kts, j)
          rho_kp1 = fnm(kts + 1) * rho(i, kts + 1, j) + fnp(kts + 1) * rho(i, kts, j)
          tendency(i, kts, j) = ( G * (rho_kp1 * turb_flux(i, kts + 1, j) - &
              rho_k * turb_flux(i, kts, j)) / dnw(kts) ) / N_PBL3D
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf - 1
          do i = i_start, i_end
            rho_k = fnm(k) * rho(i, k, j) + fnp(k) * rho(i, k - 1, j)
            rho_kp1 = fnm(k + 1) * rho(i, k + 1, j) + fnp(k + 1) * rho(i, k, j)
            tendency(i, k, j) = ( G * (rho_kp1 * turb_flux(i, k + 1, j) - &
                rho_k * turb_flux(i, k, j)) / dnw(k) ) / N_PBL3D
          end do
        end do
      end do

        ! Last layer
      do j = j_start, j_end
        do i = i_start, i_end
          rho_k = fnm(ktf) * rho(i, ktf, j) + fnp(ktf) * rho(i, ktf - 1, j)
          rho_kp1 = rho(i, ktf, j)
          tendency(i, ktf, j) = ( G * (rho_kp1 * turb_flux(i, ktf + 1, j) - &
              rho_k * turb_flux(i, ktf, j)) / dnw(ktf) ) / N_PBL3D
        end do
      end do

    end subroutine Vertical_mixing_s_with_flux


    subroutine Vertical_mixing_s_implicit (tendency, config_flags, turb_flux, phi, rdz, dnw, rho, fnm, fnp, &
              mut, c1h, c2h, dt, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                                                    !
        ! Purpose: pbl3d_scalar_implicit = 1. Replaces the explicit coupled tendency of a     !
        !          mass-point scalar phi (from Vertical_mixing_s_with_flux, same face         !
        !          densities and metrics) by a backward-Euler one.                            !
        !                                                                                    !
        ! At interior face k the closure's flux F is split into a down-gradient part         !
        ! -K dphi/dz, K = -F / (dphi/dz) where that is positive (capped at K dt rdz^2 = 100),!
        ! and a remainder (counter-gradient part, the part above the cap, the surface and    !
        ! top faces) that stays explicit. With delta = phi(n+1) - phi(n) the step is         !
        !   (I + b D_K) delta = dt * T_explicit / m,   b = -g dt / (dnw m),  m = c1h mut + c2h !
        ! where D_K is the tridiagonal diffusion operator of the K part: exactly the         !
        ! explicit increment on the right, the implicit correction on the left. Solving for  !
        ! the increment keeps single-precision round-off out of the tendency. The matrix is  !
        ! diagonally dominant (M-matrix), so the K part cannot overshoot or change sign.     !
        ! Output: tendency = m * delta / dt (coupled, as before). OPEN_ISSUES A31.           !
        !                                                                                    !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer,                     intent(in) :: ids, ide, jds, jde, kds, kde, &
                                                 ims, ime, jms, jme, kms, kme, &
                                                 its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                   intent(in)    :: dnw, fnm, fnp, c1h, c2h
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in)    :: turb_flux, phi, rdz, rho
      real, dimension (ims:ime, jms:jme),          intent(in)    :: mut
      real,                                        intent(in)    :: dt
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency

        ! Local vars
      real, parameter :: DN_CAP = 100.0
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end
      real :: grad, keff, kcap, w
      real, dimension (kts:kte+1) :: rface, kf
      real, dimension (kts:kte)   :: mk, bk, lo, di, up, rh, xs

        ! Same loop limits as Vertical_mixing_s_with_flux
      i_start = its
      i_end   = Min (ite, ide - 1)
      j_start = jts
      j_end   = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

      do j = j_start, j_end
        do i = i_start, i_end

            ! Face densities exactly as in the explicit operator
          rface(kts) = rho(i, kts, j)
          do k = kts + 1, ktf
            rface(k) = fnm(k) * rho(i, k, j) + fnp(k) * rho(i, k - 1, j)
          end do
          rface(ktf + 1) = rho(i, ktf, j)

            ! Down-gradient diffusivity at the interior faces (surface and top faces stay explicit)
          kf(kts) = 0.0
          kf(ktf + 1) = 0.0
          do k = kts + 1, ktf
            kf(k) = 0.0
            grad = (phi(i, k, j) - phi(i, k - 1, j)) * rdz(i, k, j)
            if (grad /= 0.0) then
              keff = - turb_flux(i, k, j) / grad
              if (keff > 0.0) then
                kcap = DN_CAP / (dt * rdz(i, k, j) * rdz(i, k, j))
                kf(k) = Min (keff, kcap)
              end if
            end if
          end do

            ! Tridiagonal system for the increment
          do k = kts, ktf
            mk(k) = c1h(k) * mut(i, j) + c2h(k)
            bk(k) = - G * dt / (dnw(k) * mk(k))
            up(k) = 0.0
            lo(k) = 0.0
            if (k < ktf) up(k) = - bk(k) * rface(k + 1) * kf(k + 1) * rdz(i, k + 1, j)
            if (k > kts) lo(k) = - bk(k) * rface(k) * kf(k) * rdz(i, k, j)
            di(k) = 1.0 - up(k) - lo(k)
            rh(k) = dt * tendency(i, k, j) / mk(k)
          end do

            ! Thomas algorithm (no pivoting needed: diagonally dominant)
          do k = kts + 1, ktf
            w = lo(k) / di(k - 1)
            di(k) = di(k) - w * up(k - 1)
            rh(k) = rh(k) - w * rh(k - 1)
          end do
          xs(ktf) = rh(ktf) / di(ktf)
          do k = ktf - 1, kts, -1
            xs(k) = (rh(k) - up(k) * xs(k + 1)) / di(k)
          end do

          do k = kts, ktf
            tendency(i, k, j) = mk(k) * xs(k) / dt
          end do

        end do
      end do

    end subroutine Vertical_mixing_s_implicit


    subroutine Horizontal_turb_mix (rt_tendf, ru_tendf, rv_tendf, rw_tendf, moist_tendf, qc_tendf, qr_tendf, &
              qi_tendf, qs_tendf, qg_tendf, qnc_tendf, qnr_tendf, qni_tendf, qnwfa_tendf, qnifa_tendf, tracer_tend, &
              ss, config_flags, turb_flux_u2, turb_flux_v2, turb_flux_uv, &
              turb_flux_uw, turb_flux_vw, turb_flux_w2, turb_flux_utheta, turb_flux_vtheta, turb_flux_uqv, &
              turb_flux_vqv, turb_flux_uqc, turb_flux_vqc, turb_flux_uqr, turb_flux_vqr, turb_flux_uqi, turb_flux_vqi, &
              turb_flux_uqs, turb_flux_vqs, turb_flux_uqg, turb_flux_vqg, turb_flux_uqnc, turb_flux_vqnc, &
              turb_flux_uqnr, turb_flux_vqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_uqnwfa, turb_flux_vqnwfa, &
              turb_flux_uqnifa, turb_flux_vqnifa, khx, khy, n_tracer, tracer, &
              msfux, msfuy, msfvx, msfvy, msftx, msfty, dx, dy, rdx, rdy, rdz, rdzw, fnm, fnp, cf1, cf2, cf3, &
              zx, zy, dn, dnw, rho, ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, &
              u_tmp, v_tmp, w_tmp, mut, c1h, c2h, c1f, c2f, ke_loss_h)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                               !
      ! Purpose: Performs horizontal turbulent mixing !
      !                                               !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano !
      !                                               !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      IMPLICIT NONE

      TYPE(grid_config_rec_type), INTENT(IN) :: config_flags
 
      INTEGER ,        INTENT(IN) :: ss 
      INTEGER ,        INTENT(IN) :: ids, ide, jds, jde, kds, kde, &
                                     ims, ime, jms, jme, kms, kme, &
                                     its, ite, jts, jte, kts, kte

      REAL ,           INTENT(IN) :: cf1, cf2, cf3, dx, dy

      REAL , DIMENSION( kms:kme ) ,                 INTENT(IN) :: fnm
      REAL , DIMENSION( kms:kme ) ,                 INTENT(IN) :: fnp
      REAL , DIMENSION( kms:kme ) ,                 INTENT(IN) :: dnw
      REAL , DIMENSION( kms:kme ) ,                 INTENT(IN) :: dn

      REAL , DIMENSION( ims:ime, jms:jme) ,         INTENT(IN) ::  msfux, &
                                                                   msfuy, &
                                                                   msfvx, &
                                                                   msfvy, &
                                                                   msftx, &
                                                                   msfty

      REAL , DIMENSION( its:ite, kts:kte, jts:jte), INTENT(INOUT) :: rt_tendf, &
                                                                     ru_tendf, &
                                                                     rv_tendf, &
                                                                     rw_tendf, &
                                                                     moist_tendf
      REAL , DIMENSION ( ims:ime, kms:kme, jms:jme), INTENT(INOUT) :: qc_tendf, &
           qr_tendf, qi_tendf, qs_tendf, qg_tendf, qnc_tendf, qnr_tendf, qni_tendf, qnwfa_tendf, qnifa_tendf

      REAL , DIMENSION( ims:ime, kms:kme, jms:jme, n_tracer), INTENT(INOUT) :: tracer_tend
      REAL , DIMENSION( ims:ime, kms:kme, jms:jme, n_tracer), INTENT(IN) :: tracer
      INTEGER                                               , INTENT(IN) :: n_tracer

      REAL , DIMENSION( ims:ime, kms:kme, jms:jme), INTENT(IN) :: zx, zy, rdz, rdzw, &
                                                                  rho, khx, khy
                                                                  

      REAL, DIMENSION (ims:ime, kms:kme, jms:jme), intent(IN) :: turb_flux_u2,  &
          turb_flux_v2, turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_w2, &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_uqv, turb_flux_vqv, &
          turb_flux_uqc, turb_flux_vqc, turb_flux_uqr, turb_flux_vqr, turb_flux_uqi, turb_flux_vqi, &
          turb_flux_uqs, turb_flux_vqs, turb_flux_uqg, turb_flux_vqg, turb_flux_uqnc, turb_flux_vqnc, &
          turb_flux_uqnr, turb_flux_vqnr, turb_flux_uqni, turb_flux_vqni, turb_flux_uqnwfa, turb_flux_vqnwfa, &
          turb_flux_uqnifa, turb_flux_vqnifa

      REAL, INTENT(IN) :: rdx, rdy

        ! Energy-closure diagnostic (OPEN_ISSUES A10). u_tmp/v_tmp/w_tmp are the substep
        ! state the tendencies act on, on their own staggers; mut, c1h/c2h (half levels)
        ! and c1f/c2f (full levels) decouple the mass-coupled tendencies.
      REAL, DIMENSION( ims:ime, kms:kme, jms:jme), INTENT(IN)    :: u_tmp, v_tmp, w_tmp
      REAL, DIMENSION( ims:ime, jms:jme),          INTENT(IN)    :: mut
      REAL, DIMENSION( kms:kme ),                  INTENT(IN)    :: c1h, c2h, c1f, c2f
      REAL, DIMENSION( ims:ime, kms:kme, jms:jme), INTENT(INOUT) :: ke_loss_h

        ! Local
      INTEGER :: im, i, j, k, ip1, jp1, ktf_h
      REAL, DIMENSION (its-1:ite, kts:kte, jts-1:jte) :: sf_alpha
      REAL, DIMENSION (its:ite, kts:kte, jts:jte) :: hydromet_tend
      REAL, DIMENSION (its:ite, kts:kte, jts:jte) :: ru_before, rv_before, rw_before
      REAL :: eu, ev, ew, n_sub

      call Calc_slope_factor (config_flags, msftx, msfty, dx, dy, zx, zy, rdzw, sf_alpha, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      ru_before(its:ite, kts:kte, jts:jte) = ru_tendf(its:ite, kts:kte, jts:jte)
      rv_before(its:ite, kts:kte, jts:jte) = rv_tendf(its:ite, kts:kte, jts:jte)
      rw_before(its:ite, kts:kte, jts:jte) = rw_tendf(its:ite, kts:kte, jts:jte)

      call Horizontal_mixing_u (ru_tendf, config_flags, turb_flux_u2, turb_flux_uv,  &
          msfux, msfuy, rdx, rdy, fnm, fnp, dnw, zx, zy, rdzw, rho, sf_alpha, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Horizontal_mixing_v (rv_tendf, config_flags, turb_flux_v2, turb_flux_uv,  &
          msfvx, msfvy, rdx, rdy, fnm, fnp, dnw, zx, zy, rdzw, rho, sf_alpha, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Horizontal_mixing_w (rw_tendf, config_flags, turb_flux_uw, turb_flux_vw, &
          msftx, msfty, rdx, rdy, fnm, fnp, dn, zx, zy, rdz, rho, sf_alpha, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! ---------------------------------------------------------------------------
        ! ke_loss_h = u_i * (du_i/dt)_horizontal-turbulence, at mass points, m2 s-3.
        !
        ! The three Horizontal_mixing_* calls above add the horizontal turbulent flux
        ! divergence -- including the 1/sf_alpha slope taper and the high-order stencil --
        ! to the mass-coupled tendencies, so the delta against the snapshot is exactly
        ! what the model applies. Decoupling: ru/rv carry mu at half levels, rw carries
        ! mu at full levels; the per-substep /N_PBL3D is undone so the rate is per second.
        ! u and v are taken at their own stagger and averaged to the mass point with
        ! Min(i+1, ite) / Min(j+1, jte): the tendency arrays are tile sized, so the last
        ! column/row of each patch is one-sided (sub-percent in a domain sum). w is
        ! averaged over the two bounding full levels, which are always both owned.
        !
        ! Pointwise this is NOT minus the production: they differ by the divergence of
        ! the energy flux u_i tau_ij. Compare mass-weighted domain (or column) sums with
        ! qsq_shear_h / 2; a consistent closure gives zero.
        ! ---------------------------------------------------------------------------
      n_sub = Real (Max (config_flags%pbl3d_nsteps, 1))
      ktf_h = Min (kte, kde - 1)
      do j = jts, Min (jte, jde - 1)
        jp1 = Min (j + 1, jte)
        do k = kts, ktf_h
          do i = its, Min (ite, ide - 1)
            ip1 = Min (i + 1, ite)
            eu = 0.5 * ( u_tmp(i,   k, j) * (ru_tendf(i,   k, j) - ru_before(i,   k, j))        &
                       + u_tmp(ip1, k, j) * (ru_tendf(ip1, k, j) - ru_before(ip1, k, j)) )      &
                 / (c1h(k) * mut(i, j) + c2h(k))
            ev = 0.5 * ( v_tmp(i, k, j  ) * (rv_tendf(i, k, j  ) - rv_before(i, k, j  ))        &
                       + v_tmp(i, k, jp1) * (rv_tendf(i, k, jp1) - rv_before(i, k, jp1)) )      &
                 / (c1h(k) * mut(i, j) + c2h(k))
            ew = 0.5 * ( w_tmp(i, k,     j) * (rw_tendf(i, k,     j) - rw_before(i, k,     j))  &
                         / (c1f(k)     * mut(i, j) + c2f(k))                                    &
                       + w_tmp(i, k + 1, j) * (rw_tendf(i, k + 1, j) - rw_before(i, k + 1, j))  &
                         / (c1f(k + 1) * mut(i, j) + c2f(k + 1)) )
            ke_loss_h(i, k, j) = (eu + ev + ew) * n_sub
          end do
        end do
      end do

      call Horizontal_mixing_s_with_flux (rt_tendf, config_flags, msftx, msfty, rdx, rdy, &
          fnm, fnp, zx, zy, rdz, rdzw, dnw, rho, sf_alpha, turb_flux_utheta, turb_flux_vtheta, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Horizontal_mixing_s_with_flux (moist_tendf, config_flags, msftx, msfty, rdx, rdy, &
          fnm, fnp, zx, zy, rdz, rdzw, dnw, rho, sf_alpha, turb_flux_uqv, turb_flux_vqv, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      if ( config_flags%pbl3d_scalar_mix .eq. 1 .and. ss .eq. config_flags%pbl3d_nsteps ) then
        call Mix_hydrometeor (p_qc, turb_flux_uqc, turb_flux_vqc, qc_tendf)               ! Cloud mass
        call Mix_hydrometeor (p_qr, turb_flux_uqr, turb_flux_vqr, qr_tendf)               ! Rain mass
        call Mix_hydrometeor (p_qi, turb_flux_uqi, turb_flux_vqi, qi_tendf)               ! Ice mass
        call Mix_hydrometeor (p_qs, turb_flux_uqs, turb_flux_vqs, qs_tendf)               ! Snow mass
        call Mix_hydrometeor (p_qg, turb_flux_uqg, turb_flux_vqg, qg_tendf)               ! Graupel mass
        call Mix_hydrometeor (p_qnc, turb_flux_uqnc, turb_flux_vqnc, qnc_tendf)           ! Cloud number
        call Mix_hydrometeor (p_qnr, turb_flux_uqnr, turb_flux_vqnr, qnr_tendf)           ! Rain number
        call Mix_hydrometeor (p_qni, turb_flux_uqni, turb_flux_vqni, qni_tendf)           ! Ice number
        call Mix_hydrometeor (p_qnwfa, turb_flux_uqnwfa, turb_flux_vqnwfa, qnwfa_tendf)   ! Water friendly aerosol number
        call Mix_hydrometeor (p_qnifa, turb_flux_uqnifa, turb_flux_vqnifa, qnifa_tendf)   ! Ice friendly aerosol number
      end if

      if (ss .eq. config_flags%pbl3d_nsteps .and. n_tracer .ge. param_first_scalar) then
        do im = param_first_scalar, n_tracer
          call Horizontal_mixing_s (tracer_tend(ims, kms, jms, im), config_flags, tracer(ims, kms, jms, im), &
              khx, khy, dn, dnw, rdzw, rho, fnm, fnp, cf1, cf2, cf3, rdx, rdy, zx, zy, msfux, msfvy, msftx, msfty, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        end do
      end if

    contains

      subroutine Mix_hydrometeor (p_q, turb_flux_uq, turb_flux_vq, q_tendf)

          ! Adds the horizontal turbulent mixing of one hydrometeor mass or number (index p_q in moist
          ! or scalar; nothing when the microphysics does not carry it) to its tendency q_tendf

        integer,                                     intent (in)    :: p_q
        real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: turb_flux_uq, turb_flux_vq
        real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_tendf

        if ( p_q .ge. param_first_scalar ) then
          hydromet_tend(its:ite, kts:kte, jts:jte) = q_tendf(its:ite, kts:kte, jts:jte)
          call Horizontal_mixing_s_with_flux (hydromet_tend, config_flags, msftx, msfty, rdx, rdy, &
              fnm, fnp, zx, zy, rdz, rdzw, dnw, rho, sf_alpha, turb_flux_uq, turb_flux_vq, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
          q_tendf(its:ite, kts:kte, jts:jte) = hydromet_tend(its:ite, kts:kte, jts:jte)
        end if

      end subroutine Mix_hydrometeor

    end subroutine Horizontal_turb_mix


    subroutine Calc_slope_factor (config_flags, msftx, msfty, dx, dy, zx, zy, rdzw, sf_alpha, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Calculate the slope factor to account for steep terrain   !
      !                                                                    !
      ! Author: Timothy W. Juliano                                         !
      !                                                                    !
      ! Comments: Adapted subroutine from the diffusion module             !
      !           Calculation is done at mass points                       !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent(in)  :: config_flags

      REAL, DIMENSION (ims:ime, jms:jme),          INTENT(IN)  :: msftx, msfty
      REAL,                                        INTENT(IN)  :: dx, dy
      REAL, DIMENSION (ims:ime, kms:kme, jms:jme), INTENT(IN)  :: zx, zy, rdzw
      REAL, DIMENSION (its-1:ite, kts:kte, jts-1:jte), INTENT(OUT) :: sf_alpha
      INTEGER,                                     INTENT(IN)  :: ide, jde, kde,                &
                                                                  ims, ime, jms, jme, kms, kme, &
                                                                  its, ite, jts, jte, kts, kte

        ! Local
      INTEGER :: i, j, k, i_start, i_end, j_start, j_end, ktf
      REAL    :: dxm, dym, tmpzx, tmpzy

        ! Define dimensions
      i_start = its - 1
      i_end = ite
      j_start = jts - 1
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%pbl3d_opt > 0) then
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              dxm = dx / msftx(i, j)
              dym = dy / msfty(i, j)
              tmpzx = (0.25 * ( abs(zx(i, k, j))+ abs(zx(i + 1, k, j))  &
                              + abs(zx(i, k + 1, j)) + abs(zx(i + 1, k + 1, j))) * rdzw(i, k, j) * dxm)
              tmpzy = (0.25 * ( abs(zy(i, k, j))+ abs(zy(i, k, j + 1))  &
                              + abs(zy(i, k + 1, j)) + abs(zy(i, k + 1, j + 1))) * rdzw(i, k, j) * dym)
              sf_alpha(i, k, j) = max(sqrt(tmpzx * tmpzx + tmpzy * tmpzy), 1.0)
            end do
          end do
        end do
      else
        do j = j_start, j_end
          do k = kts, ktf
            do i = i_start, i_end
              sf_alpha(i, k, j) = 1.0
            end do
          end do
        end do
      end if

    end subroutine Calc_slope_factor


    subroutine Horizontal_mixing_u (tendency, config_flags, turb_flux_u2,  turb_flux_uv, &
        msfux, msfuy, rdx, rdy, fnm, fnp, dnw, zx, zy, rdzw, rho, sf_alpha, &
        ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Add the u tendency due to horizontal turb mix             !
      !                                                                    !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                      !
      !                                                                    !
      ! Comments: Adapted subroutine from the diffusion module             !
      !           The tendency is:                                         !
      !             du / dt = - [d (u'u') / dx + d (u'v') / dy]            !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      real, intent (in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: fnm, fnp, dnw
      real, dimension (ims:ime, jms:jme), intent(in) ::  msfux, msfuy 
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdzw, rho, &
          zx, zy, turb_flux_u2, turb_flux_uv
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha

        ! Local data
      integer :: ktf
      integer :: i_start, i_end, j_start, j_end
      integer :: ie_ext, je_ext

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: &
          tf_u2_at_mass, tf_uv_at_corners

        ! Calc some indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max(ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end = Min(ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max(jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end = Min(jde - 2, jte)

        ! tf_u2_at_mass = rho * turb_flux_u2 (move flux from center of faces to mass points)
      call Prep_turb_flux_u2 (config_flags, tf_u2_at_mass, turb_flux_u2, rho, ids, ide, &
          jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! tf_uv_at_corners = rho * turb_flux_uv (move flux from center of faces to half levels at corners)
      ie_ext = 0
      je_ext = 1
      call Prep_turb_flux_uv (config_flags, tf_uv_at_corners, turb_flux_uv, rho, ie_ext, je_ext, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Calculate the u tendency due to horizontal turbulent mixing
      call Calc_htend_du (config_flags, tendency, turb_flux_u2, turb_flux_uv, tf_u2_at_mass, tf_uv_at_corners, &
          msfux, msfuy, rdx, rdy, dnw, zx, zy, rdzw, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

    end subroutine Horizontal_mixing_u


    subroutine Horizontal_mixing_v (tendency, config_flags, turb_flux_v2, turb_flux_uv, &
        msfvx, msfvy, rdx, rdy, fnm, fnp, dnw, zx, zy, rdzw, rho, sf_alpha, &
        ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Add the v tendency due to horizontal turb mix             !
      !                                                                    !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                      !
      !                                                                    !
      ! Comments: Adapted subroutine from the diffusion module             !
      !           The tendency is:                                         !
      !             dv / dt = - [d (u'v') / dx + d (v'v') / dy]            !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      real, intent (in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: fnm, fnp, dnw
      real, dimension (ims:ime, jms:jme), intent (in) :: msfvx, msfvy
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdzw, rho, &
          zx, zy, turb_flux_v2, turb_flux_uv
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha

        ! Local vars
      integer :: ktf
      integer :: i_start, i_end, j_start, j_end
      integer :: ie_ext, je_ext

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) ::  &
          tf_uv_at_corners, tf_v2_at_mass

        ! Indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
         config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
         config_flags%nested) i_end = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
         config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
         config_flags%nested) j_end = Min (jde - 1, jte)

        ! tf_uv_at_corners = rho * turb_flux_uv (move flux from center of faces to half levels at corners)
      ie_ext = 1
      je_ext = 0
      call Prep_turb_flux_uv (config_flags, tf_uv_at_corners, turb_flux_uv, rho, ie_ext, je_ext, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! tf_v2_at_mass = rho * turb_flux_v2 (move flux from center of faces to mass points)
      call Prep_turb_flux_v2 (config_flags, tf_v2_at_mass, turb_flux_v2, rho, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Calculate the v tendency due to horizontal turbulent mixing
      call Calc_htend_dv (config_flags, tendency, turb_flux_v2, turb_flux_uv, tf_v2_at_mass, tf_uv_at_corners, &
          msfvx, msfvy, rdx, rdy, dnw, zx, zy, rdzw, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

    end subroutine Horizontal_mixing_v


    subroutine Horizontal_mixing_w (tendency, config_flags, turb_flux_uw, turb_flux_vw, &
        msftx, msfty, rdx, rdy, fnm, fnp, dn, zx, zy, rdz, rho, sf_alpha, &
        ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Add the w tendency due to horizontal turb mix             !
      !                                                                    !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                      !
      !                                                                    !
      ! Comments: Adapted subroutine from the diffusion module             !
      !           The tendency is:                                         !
      !             dw / dt = - [d (u'w') / dx + d (v'w') / dy]            !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      real, intent(in) :: rdx, rdy

      real, dimension (kms:kme), intent(in) :: fnm, fnp, dn
      real, dimension (ims:ime, jms:jme), intent(in) ::  msftx, msfty

      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdz, rho, &
          zx, zy, turb_flux_uw, turb_flux_vw
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha

        ! Local data
      integer :: i, j, k, ktf
      integer :: i_start, i_end, j_start, j_end, n_offset

      real, dimension(its - 2:ite + 2, kts:kte, jts - 2:jte + 2) :: &
          tf_uw_at_full, tf_vw_at_full

        ! Calc indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
          config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
          config_flags%nested) i_end = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
          config_flags%nested) j_start = Max (jds + 1,jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
          config_flags%nested) j_end = Min (jde - 2,jte)

      n_offset = 2
      do j = j_start - n_offset, j_end + n_offset
        do k = kts + 1, ktf
          do i = i_start - n_offset, i_end + n_offset
              ! tf_uw_at_full = rho * turb_flux_uw at the center of the faces
            tf_uw_at_full(i, k, j) = turb_flux_uw(i, k, j) * (fnm(k) * rho(i, k, j) + &
                fnp(k) * rho(i, k - 1, j))
              ! tf_vw_at_full = rho * turb_flux_vw at the center of the faces
            tf_vw_at_full(i, k, j) = turb_flux_vw(i, k, j) * (fnm(k) * rho(i, k, j) + &
                fnp(k) * rho(i, k - 1, j))
          end do
        end do
      end do

        ! Calculate the w tendency due to horizontal turbulent mixing
      call Calc_htend_dw (config_flags, tendency, turb_flux_uw, turb_flux_vw, tf_uw_at_full, tf_vw_at_full, &
          msftx, msfty, rdx, rdy, dn, zx, zy, rdz, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

    end subroutine Horizontal_mixing_w


    subroutine Horizontal_mixing_s_with_flux (tendency, config_flags, msftx, msfty, rdx, rdy, fnm, fnp,   &
              zx, zy, rdz, rdzw, dnw, rho, sf_alpha, turb_flux_x, turb_flux_y, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                    !
      ! Purpose: Add the scalar tendency due to horizontal turb mix        !
      !                                                                    !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano                      !
      !                                                                    !
      ! Comments: Adapted subroutine from the diffusion module             !
      !           The tendency is:                                         !
      !             ds / dt = - [d (u's') / dx + d (v's') / dy]            !
      !                                                                    !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      real, intent (in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: fnm, fnp, dnw
      real, dimension (ims:ime, jms:jme), intent (in) ::  &
          msftx, msfty
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: rdz, &
          rdzw, zx, zy, turb_flux_x, turb_flux_y, rho
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: tendency

        ! Local vars
      integer :: ktf, i_start, i_end, j_start, j_end
      real, dimension (its-1:ite+1, kts:kte, jts-1:jte+1) ::    &
          tf_x_at_u, tf_y_at_v

        ! Define indexes
      i_start = its
      i_end   = Min (ite, ide - 1)
      j_start = jts
      j_end   = Min (jte, jde - 1)
      ktf = Min (kte, kde-1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
           config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
           config_flags%nested) i_end = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
           config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
           config_flags%nested) j_end = Min (jde - 2, jte)

        ! Scalar turbulent flux in x direction (at u points)
      call Prep_turb_flux_sx (turb_flux_x, tf_x_at_u, rho, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

        ! Scalar turbulent flux in y direction (at v points)
      call Prep_turb_flux_sy (turb_flux_y, tf_y_at_v, rho, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

        ! Calculate scalar tendency due to horizontal turbulent mixing (at mass points)
      call Calc_htend_ds (config_flags, tendency, turb_flux_x, turb_flux_y, tf_x_at_u, tf_y_at_v, rho, sf_alpha, &
          fnm, fnp, zx, zy, dnw, rdzw, msfty, msftx, rdx, rdy, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, &
          kts, kte, i_start, i_end, j_start, j_end, ktf)

    end subroutine Horizontal_mixing_s_with_flux


    subroutine Horizontal_mixing_s (tendency, config_flags, var, khx, khy, dn, dnw, rdzw, rho, fnm, fnp,  &
              cf1, cf2, cf3, rdx, rdy, zx, zy, msfux, msfvy, msftx, msfty, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                       !
        ! Purpose: Calculates tendencies of resolved variables  !
        !          at mass points due to vertical turbulent     !
        !          mixing using turbulent fluxes.               !
        !          Code adapted from module_diffusion_em.F      !
        !                                                       !
        ! Authors: Timothy W. Juliano & Pedro A. Jimenez        !
        !                                                       !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type), intent(in) :: config_flags
      integer,                     intent(in) :: ids, ide, jds, jde, kds, kde, &
                                                 ims, ime, jms, jme, kms, kme, &
                                                 its, ite, jts, jte, kts, kte

      real,                                        intent(in) :: cf1, cf2, cf3, rdx, rdy
      real, dimension (kms:kme),                   intent(in) :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent(in) :: msfux, msfvy, msftx, msfty
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: var, khx, khy, zx, zy, rdzw, rho
      real, dimension (ims:ime, kms:kme, jms:jme), intent(inout) :: tendency

        ! Local vars
      integer :: i, j, k, ktf, ktes1, ktes2
      integer :: i_start, i_end, j_start, j_end
      real :: mrdx, mrdy, tmpzx, tmpzy, rdzu, rdzv
      real, dimension(its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: H1, H2, H1avg, H2avg, &
                                                                    khx_avg, khy_avg, zx_at_m, zy_at_m

        ! Define some dimensions
      i_start = its
      i_end   = Min (ite, ide - 1)
      j_start = jts
      j_end   = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)
      ktes1 = kte - 1
      ktes2 = kte - 2

      if (config_flags%open_xs .or. config_flags%specified .or. &
        config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
        config_flags%nested) i_end   = Min (ide - 2, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
        config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
        config_flags%nested) j_end   = Min (jde - 2, jte)

! H1 = partial var over partial x

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end + 1
            khx_avg(i, k, j) = 0.25 * (khx(i - 1, k, j) + khx(i, k, j) + khx(i - 1, k + 1, j) + khx(i, k + 1, j)) * &
                                            0.5 * (rho(i - 1, k, j) + rho(i, k, j))
          end do
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end + 1
            H1avg(i, k, j) = 0.5 * (fnm(k) * (var(i - 1, k, j) + var(i, k, j)) + fnp(k) * (var(i - 1, k - 1, j) + var(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end + 1
          H1avg(i, kts, j) = 0.5 * (cf1 * var(i, 1, j) + cf2 * var(i, 2, j) + &
                                    cf3 * var(i, 3, j) + cf1 * var(i - 1, 1, j) + &
                                    cf2 * var(i - 1, 2, j) + cf3 * var(i - 1, 3, j))
          H1avg(i, ktf + 1, j) = 0.5 * (var(i, ktes1, j) + (var(i, ktes1, j) - &
                                        var(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
                                        var(i - 1, ktes1, j) + (var(i - 1, ktes1, j) - &
                                        var(i - 1, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end + 1
            tmpzx = 0.5 * (zx(i, k, j) + zx(i, k + 1, j))
            rdzu = 2. / (1. / rdzw(i, k, j) + 1. / rdzw(i - 1, k, j))
            H1(i, k, j) = -msfux(i, j) * khx_avg(i, k, j) * ( rdx * (var(i, k, j) - var(i - 1, k, j)) - tmpzx * &
                           (H1avg(i, k + 1, j) - H1avg(i, k, j)) * rdzu )
          end do
        end do
      end do

! H2 = partial var over partial y

      do j = j_start, j_end + 1
        do k = kts, ktf
          do i = i_start, i_end
            khy_avg(i, k, j) = 0.25 * (khy(i, k, j - 1) + khy(i, k, j) + khy(i, k + 1, j - 1) + khy(i, k + 1, j)) * &
                                            0.5 * (rho(i, k, j - 1) + rho(i, k, j))
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do k = kts + 1, ktf
          do i = i_start, i_end
            H2avg(i, k, j) = 0.5 * (fnm(k) * (var(i, k, j - 1) + var(i, k, j)) + fnp(k) * (var(i, k - 1, j - 1) + var(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do i = i_start, i_end
          H2avg(i, kts, j) = 0.5 * (cf1 * var(i, 1, j) + cf2 * var(i, 2, j) + &
                                    cf3 * var(i, 3, j) + cf1 * var(i, 1, j - 1) + &
                                    cf2 * var(i, 2, j - 1) + cf3 * var(i, 3, j - 1))
          H2avg(i, ktf + 1, j) = 0.5 * (var(i, ktes1, j) + (var(i, ktes1, j) - &
                                        var(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
                                        var(i, ktes1, j - 1) + (var(i, ktes1, j - 1) - &
                                        var(i, ktes2, j - 1)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

      do j = j_start, j_end + 1
        do k = kts, ktf
          do i = i_start, i_end
            tmpzy = 0.5 * (zy(i, k, j) + zy(i, k + 1, j))
            rdzv = 2. / (1. / rdzw(i, k, j) + 1. / rdzw(i, k, j - 1))
            H2(i, k, j) = -msfvy(i, j) * khy_avg(i, k, j) * ( rdy * (var(i, k, j) - var(i, k, j - 1)) - tmpzy * &
                           (H2avg(i, k + 1, j) - H2avg(i, k, j)) * rdzv )
          end do
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            H1avg(i, k, j) = 0.5 * (fnm(k) * (H1(i + 1, k, j) + H1(i, k, j)) + &
                                    fnp(k) * (H1(i + 1, k - 1, j) + H1(i, k - 1, j)))
            H2avg(i, k, j) = 0.5 * (fnm(k) * (H2(i, k, j + 1) + H2(i, k, j)) + &
                                    fnp(k) * (H2(i, k - 1, j + 1) + H2(i, k - 1, j)))
            zx_at_m(i, k, j) = 0.25 * (zx(i, k, j) + zx(i + 1, k, j) + zx(i, k + 1, j) + zx(i + 1, k + 1, j))
            zy_at_m(i, k, j) = 0.25 * (zy(i, k, j) + zy(i, k, j + 1) + zy(i, k + 1, j) + zy(i, k + 1, j + 1))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          H1avg(i, kts, j) = 0.
          H1avg(i, ktf + 1, j) = 0.
          H2avg(i, kts, j) = 0.
          H2avg(i, ktf + 1, j) = 0.
          zx_at_m(i, kts, j) = 0.25 * (zx(i, kts, j) + zx(i + 1, kts, j) + zx(i, kts + 1, j) + zx(i + 1, kts + 1, j))
          zy_at_m(i, kts, j) = 0.25 * (zy(i, kts, j) + zy(i, kts, j + 1) + zy(i, kts + 1, j) + zy(i, kts + 1, j + 1))
        end do
      end do

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            mrdx = msftx(i, j) * rdx
            mrdy = msfty(i, j) * rdy

            tendency(i, k, j) = tendency(i, k, j) + g / (dnw(k) * rdzw(i, k, j)) * &
                 ( mrdx * (H1(i + 1, k, j) - H1(i, k, j)) + mrdy * (H2(i, k, j + 1) - H2(i, k, j)) - &
                   msftx(i, j) * zx_at_m(i, k, j) * (H1avg(i, k + 1, j) - H1avg(i, k, j)) * rdzw(i, k, j) - &
                   msfty(i, j) * zy_at_m(i, k, j) * (H2avg(i, k + 1, j) - H2avg(i, k, j)) * rdzw(i, k, j) )
          end do
        end do
      end do

    end subroutine Horizontal_mixing_s


    subroutine Prep_turb_flux_u2 (config_flags, tf_at_mass, turb_flux_u2, rho, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent (in) :: ids, ide, jds, jde, kds, kde, ims, &
         ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ),  &
          intent (inout) :: tf_at_mass
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: &
          turb_flux_u2, rho

        ! Local vars
      integer :: i, j, k, ktf, i_start, i_end, j_start, j_end

        ! Define indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
         config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
         config_flags%nested) i_end = Min (ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
         config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
         config_flags%nested) j_end = Min (jde - 1, jte)

      i_start = i_start - 1

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tf_at_mass(i, k, j) = rho(i, k, j) * 0.5 * (turb_flux_u2(i, k + 1, j) + turb_flux_u2(i, k, j))
          end do
        end do
      end do

    end subroutine Prep_turb_flux_u2


    subroutine Prep_turb_flux_v2 (config_flags, tf_at_mass, turb_flux_v2, rho, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent (in) :: ids, ide, jds, jde, kds, kde, ims, &
         ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ),  &
          intent (inout) :: tf_at_mass
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: &
          turb_flux_v2, rho

        ! Local vars
      integer :: i, j, k, ktf, i_start, i_end, j_start, j_end

        ! Define indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
         config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
         config_flags%nested) i_end = Min (ide - 1, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
         config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
         config_flags%nested) j_end = Min (jde - 1, jte)

      j_start = j_start - 1

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tf_at_mass(i, k, j) = rho(i, k, j) * 0.5 * (turb_flux_v2(i, k + 1, j) + turb_flux_v2(i, k, j))
          end do
        end do
      end do

    end subroutine Prep_turb_flux_v2


    subroutine Prep_turb_flux_uv (config_flags, tf_at_corners, turb_flux_uv, rho, ie_ext, je_ext, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent (in) :: ids, ide, jds, jde, kds, kde,  &
                              ims, ime, jms, jme, kms, kme,  &
                              its, ite, jts, jte, kts, kte

      integer, intent (in) :: ie_ext, je_ext

      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), &
          intent (inout) :: tf_at_corners
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in)  &
          ::  turb_flux_uv, rho

        ! Local vars
      integer :: i, j, k, ktf, i_start, i_end, j_start, j_end
      real  :: turb_flux_avg

        ! Calc indexes
      i_start = its
      i_end = ite
      j_start = jts
      j_end = jte
      ktf = Min (kte, kde - 1)

      if (config_flags%open_xs .or. config_flags%specified .or. &
         config_flags%nested) i_start = Max (ids + 1, its)
      if (config_flags%open_xe .or. config_flags%specified .or. &
         config_flags%nested) i_end = Min (ide - 1 - ie_ext, ite)
      if (config_flags%open_ys .or. config_flags%specified .or. &
         config_flags%nested) j_start = Max (jds + 1, jts)
      if (config_flags%open_ye .or. config_flags%specified .or. &
         config_flags%nested) j_end = Min (jde - 1 - je_ext, jte)

      i_end = i_end + ie_ext
      j_end = j_end + je_ext

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            turb_flux_avg = 0.125 * (turb_flux_uv(i - 1, k, j) + turb_flux_uv(i, k, j) +  &
                turb_flux_uv(i - 1, k, j - 1) + turb_flux_uv(i, k, j - 1) + turb_flux_uv(i - 1, k + 1, j) &
                + turb_flux_uv(i, k + 1, j) + turb_flux_uv(i - 1, k + 1, j - 1) + turb_flux_uv(i, k + 1, j - 1))
            tf_at_corners(i, k, j) = turb_flux_avg * 0.25 * (rho(i - 1, k, j) + rho(i, k, j) + &
                rho(i - 1, k, j - 1) + rho(i, k, j - 1))
          end do
        end do
      end do

    end subroutine Prep_turb_flux_uv


    subroutine Prep_turb_flux_sx (turb_flux_x, tf_x_at_u, rho, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: turb_flux_x, rho
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ),  &
          intent (inout) :: tf_x_at_u

      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k
      real :: turb_flux_average

        ! tf_x_at_u = turb flux in x direction (move flux from center of faces to u points)
      do j = j_start, j_end
        do k = kts, ktf - 1
          do i = i_start, i_end + 1
            turb_flux_average = 0.25 * (turb_flux_x(i - 1, k, j) + turb_flux_x(i, k, j) +  &
               turb_flux_x(i - 1, k + 1, j) + turb_flux_x(i, k + 1, j))
            tf_x_at_u(i, k, j) = turb_flux_average  * 0.5 * (rho(i - 1, k, j) + rho(i, k, j))
          end do
        end do
      end do

       ! Top face
      do j = j_start, j_end
          do i = i_start, i_end + 1
            tf_x_at_u(i, ktf, j) = 0.25 * (turb_flux_x(i - 1, ktf, j) + turb_flux_x(i, ktf, j)) * 0.5 * (rho(i - 1, ktf, j) + rho(i, ktf, j))
          end do
      end do

    end subroutine Prep_turb_flux_sx


    subroutine Prep_turb_flux_sy (turb_flux_y, tf_y_at_v, rho, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: turb_flux_y, rho
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ),  &
          intent (inout) :: tf_y_at_v

      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k
      real :: turb_flux_average

        ! tf_y_at_v = turb flux in y direction (move flux from center of faces to v points)
      do j = j_start, j_end + 1
        do k = kts, ktf - 1
          do i = i_start, i_end
            turb_flux_average = 0.25 * (turb_flux_y(i, k, j - 1) + turb_flux_y(i, k, j) + &
                turb_flux_y(i, k + 1, j - 1) + turb_flux_y(i, k + 1, j))
            tf_y_at_v(i, k, j) = turb_flux_average * 0.5 * (rho(i, k, j - 1) + rho(i, k, j))
          end do
        end do
      end do

       ! Top face
      do j = j_start, j_end + 1
        do i = i_start, i_end
          tf_y_at_v(i, ktf, j) = 0.25 * (turb_flux_y(i, ktf, j - 1) + turb_flux_y(i, ktf, j)) * 0.5 * (rho(i, ktf, j - 1) + rho(i, ktf, j))
        end do
      end do

    end subroutine Prep_turb_flux_sy


    subroutine Calc_htend_du (config_flags, tendency, turb_flux_u2, turb_flux_uv, tf_u2_at_mass, tf_uv_at_corners, &
              msfux, msfuy, rdx, rdy, dnw, zx, zy, rdzw, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf
      real,    intent(in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: dnw
      real, dimension (ims:ime, jms:jme), intent(in) ::  msfux, msfuy
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdzw, rho, &
          zx, zy, turb_flux_u2, turb_flux_uv
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), intent(in) :: &
          tf_u2_at_mass, tf_uv_at_corners

        ! Local data
      integer :: i, j, k
      real    :: mrdx, mrdy, tmpdz, tmpalpha
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: &
          tf_u2_at_u, tf_uv_at_u, zy_at_u, zx_at_u
      real (kind = kind(tf_u2_at_u)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Calculate component related to slope in sigma surfaces
        ! tf_u2_at_u = rho * turb_flux_u2 at u points in the faces
        ! tf_uv_at_u = rho * turb_flux_uv at u points in the faces
      do j = j_start, j_end
        do i = i_start, i_end
          tf_u2_at_u(i, kts, j) = 0.5 * (turb_flux_u2(i - 1, kts, j) + &
              turb_flux_u2(i, kts, j)) * 0.5 * (rho(i - 1, kts, j) +   &
              rho(i, kts, j))
          tf_uv_at_u(i, kts, j) = 0.5 * (turb_flux_uv(i - 1, kts, j) + &
              turb_flux_uv(i, kts, j)) * 0.5 * (rho(i - 1, kts, j) +   &
              rho(i, kts, j))
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            tf_u2_at_u(i, k, j) = 0.5 * (turb_flux_u2(i - 1, k, j) + &
                turb_flux_u2(i, k, j)) * 0.25 * (rho(i - 1, k, j) +   &
                rho(i, k, j) + rho(i - 1, k - 1, j) + rho(i, k - 1, j))
            tf_uv_at_u(i, k, j) = 0.5 * (turb_flux_uv(i - 1, k, j) + &
                turb_flux_uv(i, k, j)) * 0.25 * (rho(i - 1, k, j) +   &
                rho(i, k, j) + rho(i - 1, k - 1, j) + rho(i, k - 1, j))
              ! Horizontal derivatives of z at u points
            zy_at_u(i, k, j) = 0.125 * (zy(i - 1, k, j) + zy(i, k, j) + &
                zy(i - 1, k, j + 1) + zy(i, k, j + 1) + zy(i - 1, k + 1, j) + &
                zy(i, k + 1, j) + zy(i - 1, k + 1, j + 1) + zy(i, k + 1, j + 1))
            zx_at_u(i, k, j) = 0.5 * (zx(i, k, j) + zx(i, k + 1 , j))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          tf_u2_at_u(i, ktf + 1, j) = 0.0
          tf_uv_at_u(i, ktf + 1, j) = 0.0
          zx_at_u(i, kts, j) = 0.5 * (zx(i, kts, j) + zx(i, kts + 1 , j))
          zy_at_u(i, kts, j) = 0.125 * (zy(i - 1, kts, j) + zy(i, kts, j) + &
              zy(i - 1, kts, j + 1) + zy(i, kts, j + 1) + zy(i - 1, kts + 1, j) + &
              zy(i, kts + 1, j) + zy(i - 1, kts + 1, j + 1) + zy(i, kts + 1, j + 1))
        end do
      end do

        ! Calc tendency using coordinate transform (sigma to cartesian)
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            mrdx = msfux(i, j) * rdx
            mrdy = msfuy(i, j) * rdy
            tmpdz = (1.0 / rdzw(i, k, j) + 1.0 / rdzw(i - 1, k, j)) / 2.0
            tmpalpha = 0.5 * (sf_alpha(i - 1, k, j) + sf_alpha(i, k, j))
            tendency(i, k, j) = tendency(i, k, j) + ( G * tmpdz / dnw(k) *             &
               (mrdx * (tf_u2_at_mass(i, k, j) - tf_u2_at_mass(i - 1, k, j)) +                      &
                mrdy * (tf_uv_at_corners(i, k, j + 1) - tf_uv_at_corners(i, k, j)) -                      &
                msfux(i, j) * zx_at_u(i, k, j) * (tf_u2_at_u(i, k + 1, j) - tf_u2_at_u(i, k, j)) / tmpdz - &
                msfuy(i, j) * zy_at_u(i, k, j) * (tf_uv_at_u(i, k + 1, j) - tf_uv_at_u(i, k, j)) / tmpdz) ) / (N_PBL3D * tmpalpha)
          end do
        end do
      end do

    end subroutine Calc_htend_du


    subroutine Calc_htend_dv (config_flags, tendency, turb_flux_v2, turb_flux_uv, tf_v2_at_mass, tf_uv_at_corners, &
              msfvx, msfvy, rdx, rdy, dnw, zx, zy, rdzw, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf
      real,    intent(in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: dnw
      real, dimension (ims:ime, jms:jme), intent(in) ::  msfvx, msfvy
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdzw, rho, &
          zx, zy, turb_flux_v2, turb_flux_uv
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1), intent(in) :: &
          tf_v2_at_mass, tf_uv_at_corners

        ! Local data
      integer :: i, j, k
      real    :: mrdx, mrdy, tmpdz, tmpalpha
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: &
          tf_v2_at_v, tf_uv_at_v, zy_at_v, zx_at_v
      real (kind = kind(tf_v2_at_v)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Calculate component related to slope in sigma surfaces
        ! tf_uv_at_v = rho * turb_flux_uv at v points in the faces
        ! tf_v2_at_v = rho * turb_flux_v2 at v points in the faces
      do j = j_start, j_end
        do i = i_start, i_end
          tf_uv_at_v(i, kts, j) = 0.5 * (turb_flux_uv(i, kts, j - 1) + &
              turb_flux_uv(i, kts, j)) * 0.5 * (rho(i, kts, j - 1) +   &
              rho(i, kts, j))
          tf_v2_at_v(i, kts, j) = 0.5 * (turb_flux_v2(i, kts, j - 1) + &
              turb_flux_v2(i, kts, j)) * 0.5 * (rho(i, kts, j - 1) +   &
              rho(i, kts, j))
        end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            tf_uv_at_v(i, k, j) = 0.5 * (turb_flux_uv(i, k, j - 1) + &
                turb_flux_uv(i, k, j)) * 0.25 * (rho(i, k, j - 1) +   &
                rho(i, k, j) + rho(i, k - 1, j - 1) + rho(i, k - 1, j))
            tf_v2_at_v(i, k, j) = 0.5 * (turb_flux_v2(i, k, j - 1) + &
                turb_flux_v2(i, k, j)) * 0.25 * (rho(i, k, j - 1) +   &
                rho(i, k, j) + rho(i, k - 1, j - 1) + rho(i, k - 1, j))
              ! Horiontal derivatives of z at v points
            zx_at_v(i, k, j) = 0.125 * (zx(i, k, j) + zx(i + 1, k, j) +     &
                zx(i, k, j - 1) + zx(i + 1, k, j - 1) + zx(i, k + 1, j) +   &
                zx(i + 1, k + 1, j) + zx(i, k + 1, j - 1) + zx(i + 1, k + 1, j - 1))
            zy_at_v(i, k, j) = 0.5 * (zy(i, k, j) + zy(i, k + 1 , j))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          tf_uv_at_v(i, ktf + 1,j)= 0.0
          tf_v2_at_v(i, ktf + 1, j) = 0.0
          zx_at_v(i, kts, j) = 0.125 * (zx(i, kts, j) + zx(i + 1, kts, j) +     &
              zx(i, kts, j - 1) + zx(i + 1, kts, j - 1) + zx(i, kts + 1, j) + &
              zx(i + 1, kts + 1, j) + zx(i, kts + 1, j - 1) + zx(i + 1, kts + 1, j - 1))
          zy_at_v(i, kts, j) = 0.5 * (zy(i, kts, j) + zy(i, kts + 1 , j))
        end do
      end do

        ! Calc tendency using coordinate transform (sigma to cartesian)
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            mrdx = msfvx(i, j) * rdx
            mrdy = msfvy(i, j) * rdy
            tmpdz = (1.0 / rdzw(i, k, j) + 1.0 / rdzw(i, k, j - 1)) / 2.0
            tmpalpha = 0.5 * (sf_alpha(i, k, j - 1) + sf_alpha(i, k, j))
            tendency(i, k, j) = tendency(i, k, j) + ( G * tmpdz / dnw(k) * &
                (mrdy * (tf_v2_at_mass(i, k, j) - tf_v2_at_mass(i, k, j - 1)) +       &
                 mrdx * (tf_uv_at_corners(i + 1, k, j) - tf_uv_at_corners(i, k, j)) -       &
                 msfvx(i, j) * zx_at_v(i, k, j) * (tf_uv_at_v(i, k + 1, j) - tf_uv_at_v(i, k, j)) / tmpdz - &
                 msfvy(i, j) * zy_at_v(i, k, j) * (tf_v2_at_v(i, k + 1, j) - tf_v2_at_v(i, k, j)) / tmpdz) ) / (N_PBL3D * tmpalpha)
          end do
        end do
      end do

    end subroutine Calc_htend_dv


    subroutine Calc_htend_dw (config_flags, tendency, turb_flux_uw, turb_flux_vw, tf_uw_at_full, tf_vw_at_full, &
              msftx, msfty, rdx, rdy, dn, zx, zy, rdz, rho, sf_alpha, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf
      real,    intent(in) :: rdx, rdy

      real, dimension (kms:kme), intent (in) :: dn
      real, dimension (ims:ime, jms:jme), intent(in) ::  msftx, msfty
      real, dimension (its:ite, kts:kte, jts:jte), intent(inout) :: tendency
      real, dimension (ims:ime, kms:kme, jms:jme), intent(in) :: rdz, rho, &
          zx, zy, turb_flux_uw, turb_flux_vw
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha
      real, dimension (its - 2:ite + 2, kts:kte, jts - 2:jte + 2), intent(in) :: &
          tf_uw_at_full, tf_vw_at_full

        ! Local data
      integer :: i, j, k
      real    :: mrdx, mrdy, tmpalpha
      real, dimension (its - 2:ite + 2, kts:kte, jts - 2:jte + 2) :: &
          tf_uw_at_mass, tf_vw_at_mass, zy_at_w, zx_at_w
      real (kind = kind(tf_uw_at_mass)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Calculate component related to slope in sigma surfaces
        ! tf_uw_at_mass = turb_flux_uw * rho at mass points
        ! tf_vw_at_mass = turb_flux_vw * rho at mass points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tf_uw_at_mass(i, k, j) = 0.5 * (turb_flux_uw(i, k, j) + turb_flux_uw(i, k + 1, j)) *  rho(i, k, j)
            tf_vw_at_mass(i, k, j) = 0.5 * (turb_flux_vw(i, k, j) + turb_flux_vw(i, k + 1, j)) *  rho(i, k, j)
              ! Horiontal derivatives of z at center of faces
            zx_at_w(i, k, j) = 0.5 * (zx(i, k, j) + zx(i + 1, k, j))
            zy_at_w(i, k, j) = 0.5 * (zy(i, k, j) + zy(i, k, j + 1))
          end do
        end do
      end do

        ! Lid
      do j = j_start, j_end
        do i = i_start, i_end
          tf_uw_at_mass(i, ktf + 1, j) = 0.0
          tf_vw_at_mass(i, ktf + 1, j) = 0.0
        end do
      end do

        ! Calc tendency using coordinate transform (sigma to cartesian)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            mrdx = msftx(i, j) * rdx
            mrdy = msfty(i, j) * rdy
            tmpalpha = 0.5 * (sf_alpha(i, k - 1, j) + sf_alpha(i, k, j))
            tendency(i, k, j) = tendency(i, k, j) + ( G / (dn(k) * rdz(i, k, j)) * (   &
                mrdx * ((8.0 * (tf_uw_at_full(i + 1, k, j) - tf_uw_at_full(i - 1, k, j))) -  &
                (tf_uw_at_full(i + 2, k, j) - tf_uw_at_full(i - 2, k, j))) / 12.0 +          &
                mrdy * (8.0 * (tf_vw_at_full(i, k, j + 1) - tf_vw_at_full(i, k, j - 1)) -    &
                (tf_vw_at_full(i, k, j + 2) - tf_vw_at_full(i, k, j - 2))) / 12.0 -          &
                rdz(i, k, j) * (msftx(i, j) * zx_at_w(i, k, j) * (tf_uw_at_mass(i, k, j) - tf_uw_at_mass(i, k - 1, j)) +  &
                                msfty(i, j) * zy_at_w(i, k, j) * (tf_vw_at_mass(i, k, j) - tf_vw_at_mass(i, k - 1, j))) ) ) / (N_PBL3D * tmpalpha)
          end do
        end do
      end do

    end subroutine Calc_htend_dw


    subroutine Calc_htend_ds (config_flags, tendency, turb_flux_x, turb_flux_y, tf_x_at_u, tf_y_at_v, rho, sf_alpha, &
              fnm, fnp, zx, zy, dnw, rdzw, msfty, msftx, rdx, rdy, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, &
              kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent(in) :: ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      real, intent (in) :: rdx, rdy
      real, dimension (kms:kme), intent (in) :: fnm, fnp, dnw
      real, dimension (ims:ime, jms:jme), intent (in) :: msftx, msfty
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: turb_flux_x, &
          turb_flux_y, rho, rdzw, zx, zy
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent(in) :: sf_alpha
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ),  &
          intent (in) :: tf_x_at_u, tf_y_at_v
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: tendency

      integer, intent(in) :: i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k
      real :: mrdx, mrdy
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1 ) ::  &
          tf_x_at_full, tf_y_at_full, zx_at_m, zy_at_m
      real (kind = kind(tf_x_at_full)) :: N_PBL3D

      N_PBL3D = config_flags%pbl3d_nsteps

        ! Calculate component related to slope in sigma surfaces
        ! tf_x_at_full = turb_flux_x * rho at the center of the faces
        ! tf_y_at_full = turb_flux_y * rho at the center of the faces
      do j = j_start, j_end
        do i = i_start, i_end
          tf_x_at_full(i, kts, j) = turb_flux_x(i, kts, j) * rho(i, kts, j)
          tf_y_at_full(i, kts, j) = turb_flux_y(i, kts, j) * rho(i, kts, j)
          end do
      end do

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            tf_x_at_full(i, k, j) = turb_flux_x(i, k, j) * (fnm(k) * rho(i, k, j) + &
                fnp(k) * rho(i, k - 1, j))
            tf_y_at_full(i, k, j) = turb_flux_y(i, k, j) * (fnm(k) * rho(i, k, j) + &
                fnp(k) * rho(i, k - 1, j))
            zx_at_m(i, k, j) = 0.25 * (zx(i, k, j) + zx(i + 1, k, j) + &
                zx(i, k + 1, j) + zx(i + 1, k + 1, j))
            zy_at_m(i, k, j) = 0.25 * (zy(i, k, j) + zy(i, k, j + 1) + &
                zy(i, k + 1, j) + zy(i, k + 1, j + 1))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          tf_x_at_full(i, ktf + 1, j) = 0.0
          tf_y_at_full(i, ktf + 1, j) = 0.0
          zx_at_m(i, kts, j) = 0.25 * (zx(i, kts, j) + zx(i + 1, kts, j) + &
              zx(i, kts + 1, j) + zx(i + 1, kts + 1, j))
          zy_at_m(i, kts, j) = 0.25 * (zy(i, kts, j) + zy(i, kts, j + 1) + &
              zy(i, kts + 1, j) + zy(i, kts + 1, j + 1))
        end do
      end do

        ! Calc tendency using coordinate transform (sigma to cartesian)
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            mrdx = msftx(i, j) * rdx
            mrdy = msfty(i, j) * rdy
            tendency(i, k, j) = tendency(i, k, j) + ( G / (dnw(k) * rdzw(i, k, j)) * (  &
                mrdx * (tf_x_at_u(i + 1, k, j) - tf_x_at_u(i, k, j)) +                &
                mrdy * (tf_y_at_v(i, k, j + 1) - tf_y_at_v(i, k, j)) -                &
                msftx(i, j) * zx_at_m(i, k, j) * (tf_x_at_full(i, k + 1, j) - tf_x_at_full(i, k, j)) * rdzw(i, k, j) - &
                msfty(i, j) * zy_at_m(i, k, j) * (tf_y_at_full(i, k + 1, j) - tf_y_at_full(i, k, j)) * rdzw(i, k, j)) ) / (N_PBL3D * sf_alpha(i, k, j))
          end do
        end do
      end do

    end subroutine Calc_htend_ds


    subroutine Calc_q_sq_l2p5 (grid, config_flags, u, v, w, zx, zy, t, qv, rho, thetav, tsk, t2, q2, psfc, ust, hfx, &
              du_dx_faces, du_dy_faces, du_dz_faces, dv_dx_faces, dv_dy_faces, dv_dz_faces, dw_dx_faces, dw_dy_faces, dw_dz_faces, &
              dthetav_dz_faces, q_sq, q_sq_prog, q_sq_tend, q_sq_vdiff_tend, q_sq_hdiff_tend, q_sq_shear_tend, q_sq_buoyancy_tend, &
              q_sq_dissip_tend, l_master_at_face, l_master_at_mass, l_boulac, turb_flux_u2_face, turb_flux_v2_face, turb_flux_w2_face, &
              turb_flux_uv_face, turb_flux_uw_face, turb_flux_vw_face, turb_flux_wtheta_v_face, turb_flux_u2, turb_flux_v2, &
              turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, dn, dnw, fnm, fnp, &
              msftx, msfty, msfux, msfuy, msfvx, msfvy, mut, c1, c2, z_at_mass, rdx, rdy, rdz, rdzw, cf1, cf2, cf3, dt, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculates derivatives and fluxes at mass points                              !
      !          to prepare for prognostic TKE equation (level 2.5)                            !
      !                                                                                        !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                                          !
      !                                                                                        !
      ! Method: 1) Follows module_diffusion_em to calc shear, buoyancy, and dissipation terms  !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (domain)              , intent (in) :: grid
      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: u, v, w, zx, zy, t, qv, rho, thetav
      real, dimension (ims:ime, jms:jme),          intent (in)    :: tsk, t2, q2, psfc, ust, hfx
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dx_faces, du_dy_faces, du_dz_faces, &
                                                                     dv_dx_faces, dv_dy_faces, dv_dz_faces, &
                                                                     dw_dx_faces, dw_dy_faces, dw_dz_faces, &
                                                                     dthetav_dz_faces
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_vdiff_tend,    &
                                                                     q_sq_hdiff_tend,    &
                                                                     q_sq_shear_tend,    &
                                                                     q_sq_buoyancy_tend, &
                                                                     q_sq_dissip_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq, l_master_at_face
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_boulac
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: l_master_at_mass
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: turb_flux_u2, turb_flux_v2, turb_flux_w2, &
                                                                     turb_flux_uv, turb_flux_uw, turb_flux_vw, &
                                                                     turb_flux_wtheta_v
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: turb_flux_u2_face, turb_flux_v2_face, turb_flux_w2_face, &
                                                                     turb_flux_uv_face, turb_flux_uw_face, turb_flux_vw_face, &
                                                                     turb_flux_wtheta_v_face
      real, dimension (kms:kme),                   intent (in)    :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)    :: msftx, msfty, msfux, msfuy, msfvx, msfvy
      real, dimension (ims:ime, jms:jme),          intent (in)    :: mut
      real, dimension (kms:kme),                   intent (in)    :: c1, c2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: z_at_mass, rdz, rdzw
      real,                                        intent (in)    :: rdx, rdy, cf1, cf2, cf3, dt
      integer, intent (in) :: ids, ide, jds, jde, kds, kde,  &
                              ims, ime, jms, jme, kms, kme,  &
                              ips, ipe, jps, jpe, kps, kpe,  &
                              its, ite, jts, jte, kts, kte

        ! Local vars
      real, dimension (its:ite, kts:kte, jts:jte) :: du_dz_mass, dv_dz_mass, dw_dz_mass, du_dx_mass, dv_dx_mass, dw_dx_mass, &
           du_dy_mass, dv_dy_mass, dw_dy_mass, dthetav_dz_mass, dqv_dz_mass
      real, dimension (its:ite, jts:jte)          :: thetav_sk

      call Calc_wind_derivatives_at_mass (config_flags, u, v, w, zx, zy, du_dz_mass, dv_dz_mass, dw_dz_mass, &
          du_dx_mass, dv_dx_mass, dw_dx_mass, du_dy_mass, dv_dy_mass, dw_dy_mass, rdzw, dn, dnw, fnm, fnp, msftx, msfty, &
          msfux, msfuy, msfvx, msfvy, rdx, rdy, cf1, cf2, cf3, ids, ide, jds, jde, kds, kde, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Calc_surface_thetav (tsk, t2, q2, psfc, thetav_sk, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Calc_mass_var_derivatives_at_mass (thetav, thetav_sk, q2, qv, dthetav_dz_mass, dqv_dz_mass, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Fill_fluxes_mass_with_fluxes_face (turb_flux_u2_face, turb_flux_v2_face, turb_flux_w2_face, turb_flux_uv_face, turb_flux_uw_face, &
          turb_flux_vw_face, turb_flux_wtheta_v_face, turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw, &
          turb_flux_wtheta_v, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Fill_l_mass_with_l_face (l_master_at_face, l_master_at_mass, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        ! Calc TKE tendency
      call Calc_q_sq_rhs (grid, config_flags, zx, zy, du_dz_mass, dv_dz_mass, dw_dz_mass, du_dx_mass, dv_dx_mass, dw_dx_mass, &
          du_dy_mass, dv_dy_mass, dw_dy_mass, dthetav_dz_mass, q_sq, q_sq_prog, q_sq_tend, &
          q_sq_vdiff_tend, q_sq_hdiff_tend, q_sq_shear_tend, q_sq_buoyancy_tend, q_sq_dissip_tend, &
          l_master_at_face, l_master_at_mass, l_boulac, turb_flux_u2, turb_flux_v2, turb_flux_w2, &
          turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, dn, dnw, fnm, fnp, &
          msftx, msfty, msfux, msfuy, msfvx, msfvy, mut, c1, c2, z_at_mass, rdx, rdy, rdz, rdzw, cf1, cf2, cf3, dt, &
          ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

    end subroutine Calc_q_sq_l2p5


    subroutine Calc_wind_derivatives_at_mass (config_flags, u, v, w, zx, zy, du_dz, dv_dz, dw_dz, &
              du_dx, dv_dx, dw_dx, du_dy, dv_dy, dw_dy, rdzw, dn, dnw, fnm, fnp, msftx, msfty, &
              msfux, msfuy, msfvx, msfvy, rdx, rdy, cf1, cf2, cf3, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                                                         !
        ! Purpose: Calculate spatial derivatives of the wind variables at mass points             !
        !                                                                                         !
        ! Authors: Timothy W. Juliano & Pedro A. Jimenez                                          !
        !                                                                                         !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (grid_config_rec_type),                 intent (in)  :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: u, v, w, zx, zy, rdzw
      real, dimension (kms:kme), intent (in)                    :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx, msfty, msfux, msfuy, msfvx, msfvy
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: du_dz, dv_dz, dw_dz, &
                                                                   du_dx, dv_dx, dw_dx, &
                                                                   du_dy, dv_dy, dw_dy
      real,                                        intent (in)  :: rdx, rdy, cf1, cf2, cf3

        ! Local vars: u and v divided by their map factors, at u points (x derivatives) and at v points (y derivatives)
      real, dimension (its - 1:ite + 1, kts:kte, jts - 1:jte + 1) :: u_mux, v_mvx, u_muy, v_mvy

      call Calc_duv_dz_at_mass (u, 1, 0, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dz)

      call Calc_duv_dz_at_mass (v, 0, 1, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dz)

      call Calc_dw_dz_at_mass (w, rdzw, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dw_dz)

      call Scale_uv_by_map_factors (config_flags, u, v, msfux, msfuy, msfvx, msfvy, u_mux, v_mvx, u_muy, v_mvy, &
          ide, jds, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      call Calc_duv_dx (.false., u_mux, msfux, zx, rdzw, dn, dnw, fnm, fnp, msftx, rdx, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dx)

      call Calc_duv_dx (.false., v_mvx, msfvx, zx, rdzw, dn, dnw, fnm, fnp, msftx, rdx, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dx)

      call Calc_dw_dx (.false., w, zx, rdzw, msftx, rdx, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, dw_dx)

      call Calc_duv_dy (.false., u_muy, msfuy, zy, rdzw, dn, dnw, fnm, fnp, msfty, rdy, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dy)

      call Calc_duv_dy (.false., v_mvy, msfvy, zy, rdzw, dn, dnw, fnm, fnp, msfty, rdy, cf1, cf2, cf3, &
          ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dy)

      call Calc_dw_dy (.false., w, zy, rdzw, msfty, rdy, ide, jde, kde, ims, ime, jms, jme, kms, kme, &
          its, ite, jts, jte, kts, kte, dw_dy)

    end subroutine Calc_wind_derivatives_at_mass


    subroutine Calc_duv_dz_at_mass (vel, di, dj, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dvel_dz)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                       !
      ! Purpose: Calculate du/dz or dv/dz at the mass points: the component is interpolated   !
      !          to full levels at its own points, then averaged to the center of the faces   !
      !          from its two horizontal neighbours (i, j) and (i + di, j + dj): (di, dj) =    !
      !          (1, 0) for u, (0, 1) for v.                                                  !
      !                                                                                       !
      ! Authors: Timothy W. Juliano & Pedro A. Jimenez                                        !
      !                                                                                       !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: vel, rdzw
      integer,                                     intent (in)  :: di, dj
      real, dimension (kms:kme), intent (in)                    :: dn, dnw, fnm, fnp
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dvel_dz
      real,                                        intent (in)  :: cf1, cf2, cf3

        ! Local vars
      integer :: i, j, k
      real    :: cft1, cft2
      real, dimension (its-1:ite+1, kts:kte, jts-1:jte+1) :: vel_at_full
      real, dimension (its:ite, kts:kte, jts:jte)   :: vel_at_face
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end

        ! Define some indexes
      ktes1 = kte - 1
      ktes2 = kte - 2
      cft2 = - 0.5 * dnw(ktes1) / dn(ktes1)
      cft1 = 1.0 - cft2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Interpolate from half levels to full levels
      do j = j_start, j_end + dj
        do k = kts + 1, ktf
          do i = i_start, i_end + di
            vel_at_full(i, k, j) = fnm(k) * vel(i, k, j) + fnp(k) * vel(i, k - 1, j)
          end do
        end do
      end do

      do j = j_start, j_end + dj
        do i = i_start, i_end + di
            ! Surface
          vel_at_full(i, 1, j) =  cf1 * vel(i, 1, j) + cf2 * vel(i, 2, j) + cf3 * vel(i, 3, j)
            ! Top face
          vel_at_full(i, kte, j) =  cft1 * vel(i, ktes1, j) + cft2 * vel(i, ktes2, j)
        end do
      end do

        ! Calculate the component at the center of the faces
      do j = j_start, j_end
        do k = kts, kte
          do i = i_start, i_end
            vel_at_face(i, k, j) = 0.5 * (vel_at_full(i, k, j) + vel_at_full(i + di, k, j + dj))
          end do
        end do
      end do

        ! Calculate derivative at the mass points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            dvel_dz(i, k, j) = (vel_at_face(i, k + 1, j) - vel_at_face(i, k, j)) * rdzw(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Top
          dvel_dz(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_duv_dz_at_mass


    subroutine Calc_dw_dz_at_mass (w, rdzw, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dw_dz)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Calculate dw/dz                             !
      !                                                      !
      ! Authors: Timothy W. Juliano & Pedro A. Jimenez       !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: w, rdzw
      integer,                                     intent (in)  :: ide, jde, kde,                 &
                                                                   ims, ime, jms, jme, kms, kme,  &
                                                                   its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dw_dz

        ! Local vars
      integer :: i, j, k
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Calculate derivative at the mass points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            dw_dz(i, k, j) = (w(i, k + 1, j) - w(i, k, j)) * rdzw(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Top
          dw_dz(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_dw_dz_at_mass


    subroutine Calc_surface_thetav (tsk, t2, q2, psfc, thetav_sk, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, jms:jme),          intent (in)  :: tsk, t2, q2, psfc
      real, dimension (its:ite, jts:jte),          intent (out) :: thetav_sk
      integer,                                     intent (in)  :: ide, jde, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
        ! Local vars
      integer :: i, j
      integer :: i_start, i_end, j_start, j_end
      real    :: sqv, theta_sk

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      do j = j_start, j_end
        do i = i_start, i_end
          sqv = q2(i, j) / (1.0 + q2(i, j))
          theta_sk = t2(i, j) * (100000. / psfc(i, j)) ** rcp
          thetav_sk(i, j) = theta_sk * (1.0 + P608 * sqv)
        end do
      end do

    end subroutine Calc_surface_thetav


    subroutine Calc_mass_var_derivatives_at_mass (thetav, thetav_sk, q2, qv, dthetav_dz, dqv_dz, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                     !
      ! Purpose: Calculate spatial derivatives of mass variables at mass points             !
      !                                                                                     !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano                                      !
      !                                                                                     !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (kms:kme),                   intent (in)  :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: thetav, qv
      real, dimension (its:ite, jts:jte),          intent (in)  :: thetav_sk
      real, dimension (ims:ime, jms:jme),          intent (in)  :: q2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: rdzw
      integer,                                     intent (in)  :: ids, ide, jds, jde, kds, kde, &
                                                                   ims, ime, jms, jme, kms, kme, &
                                                                   its, ite, jts, jte, kts, kte
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: dthetav_dz, dqv_dz
      real,                                        intent (in)  :: cf1, cf2, cf3

        ! Calculate thetav derivatives
      call Calc_dmassvar_dz_at_mass (var=thetav, thetav_sk=thetav_sk, rdzw=rdzw, dn=dn, dnw=dnw, fnm=fnm, fnp=fnp, &
          cf1=cf1, cf2=cf2, cf3=cf3, ide=ide, jde=jde, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, dvar_dz=dthetav_dz)

        ! Calculate thetav derivatives
      call Calc_dmassvar_dz_at_mass (var=qv, q2=q2, rdzw=rdzw, dn=dn, dnw=dnw, fnm=fnm, fnp=fnp, &
          cf1=cf1, cf2=cf2, cf3=cf3, ide=ide, jde=jde, kde=kde, ims=ims, ime=ime, jms=jms, jme=jme, kms=kms, kme=kme, &
          its=its, ite=ite, jts=jts, jte=jte, kts=kts, kte=kte, dvar_dz=dqv_dz)

    end subroutine Calc_mass_var_derivatives_at_mass


    subroutine Calc_dmassvar_dz_at_mass (var, thetav_sk, q2, rdzw, dn, dnw, fnm, fnp, cf1, cf2, cf3, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dvar_dz)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Calculate partial var over partial z        !
      !                                                      !
      ! Authors: Pedro A. Jimenez & Timothy W. Juliano       !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme),  intent (in)  :: var, rdzw
      real, dimension (its:ite, jts:jte), optional, intent (in)  :: thetav_sk
      real, dimension (ims:ime, jms:jme), optional, intent (in)  :: q2
      real, dimension (kms:kme),                    intent (in)  :: dn, dnw, fnm, fnp
      integer,                                      intent (in)  :: ide, jde, kde,                  &
                                                                    ims, ime, jms, jme, kms, kme,   &
                                                                    its, ite, jts, jte, kts, kte

      real, dimension (its:ite, kts:kte, jts:jte),  intent (out) :: dvar_dz
      real,                                         intent (in)  :: cf1, cf2, cf3

        ! Local vars
      integer :: i, j, k
      real    :: cft1, cft2
      integer :: ktf, ktes1, ktes2, i_start, i_end, j_start, j_end
      real, dimension (its:ite, kts:kte, jts:jte) :: var_at_full

        ! Define some indexes
      ktes1 = kte - 1
      ktes2 = kte - 2
      cft2 = - 0.5 * dnw(ktes1) / dn(ktes1)
      cft1 = 1.0 - cft2

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

        ! Interpolate from half levels to full levels
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            var_at_full(i, k, j) = fnm(k) * var(i, k, j) + fnp(k) * var(i, k - 1, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Surface
          if (PRESENT(thetav_sk)) then
            var_at_full(i, 1, j) =  thetav_sk(i, j) - 300.
          end if
          if (PRESENT(q2)) then
            var_at_full(i, 1, j) =  q2(i, j)
          end if
            ! Top face
          var_at_full(i, kte, j) =  cft1 * var(i, ktes1, j) + cft2 * var(i, ktes2, j)
        end do
      end do

        ! Calculate derivative at mass points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            dvar_dz(i, k, j) = (var_at_full(i, k + 1, j) - var_at_full(i, k, j)) * rdzw(i, k, j)
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
            ! Top
          dvar_dz(i, kte, j) = 0.0
        end do
      end do

    end subroutine Calc_dmassvar_dz_at_mass


    subroutine Fill_fluxes_mass_with_fluxes_face (tff_u2, tff_v2, tff_w2, tff_uv, tff_uw, tff_vw, tff_wthv, &
              tfm_u2, tfm_v2, tfm_w2, tfm_uv, tfm_uw, tfm_vw, tfm_wthv, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)   :: tff_u2, tff_v2, tff_w2, tff_uv, tff_uw, tff_vw, tff_wthv
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)  :: tfm_u2, tfm_v2, tfm_w2, tfm_uv, tfm_uw, tfm_vw, tfm_wthv
      integer,                                     intent (in)   :: ide, jde, kde,                  &
                                                                    ims, ime, jms, jme, kms, kme,   &
                                                                    its, ite, jts, jte, kts, kte

        ! Local vars
      integer :: i, j, k
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            tfm_u2(i, k, j) = 0.5 * ( tff_u2(i, k + 1, j) + tff_u2(i, k, j) )
            tfm_v2(i, k, j) = 0.5 * ( tff_v2(i, k + 1, j) + tff_v2(i, k, j) )
            tfm_w2(i, k, j) = 0.5 * ( tff_w2(i, k + 1, j) + tff_w2(i, k, j) )
            tfm_uv(i, k, j) = 0.5 * ( tff_uv(i, k + 1, j) + tff_uv(i, k, j) )
            tfm_uw(i, k, j) = 0.5 * ( tff_uw(i, k + 1, j) + tff_uw(i, k, j) )
            tfm_vw(i, k, j) = 0.5 * ( tff_vw(i, k + 1, j) + tff_vw(i, k, j) )
            tfm_wthv(i, k, j) = 0.5 * ( tff_wthv(i, k + 1, j) + tff_wthv(i, k, j) )
          end do
        end do
      end do

    end subroutine Fill_fluxes_mass_with_fluxes_face


    subroutine Fill_l_mass_with_l_face (l_master_at_face, l_master_at_mass, &
              ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)

      implicit none

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)   :: l_master_at_face
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)  :: l_master_at_mass
      integer,                                     intent (in)   :: ide, jde, kde,                  &
                                                                    ims, ime, jms, jme, kms, kme,   &
                                                                    its, ite, jts, jte, kts, kte

        ! Local vars
      integer :: i, j, k
      integer :: ktf, i_start, i_end, j_start, j_end

        ! Define some indexes
      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)
      ktf = Min (kte, kde - 1)

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            l_master_at_mass(i, k, j) = 0.5 * ( l_master_at_face(i, k + 1, j) + l_master_at_face(i, k, j) )
          end do
        end do
      end do

    end subroutine Fill_l_mass_with_l_face


    subroutine Calc_q_sq_rhs (grid, config_flags, zx, zy, du_dz, dv_dz, dw_dz, du_dx, dv_dx, dw_dx, du_dy, dv_dy, dw_dy, &
              dthetav_dz, q_sq, q_sq_prog, q_sq_tend, q_sq_vdiff_tend, q_sq_hdiff_tend, q_sq_shear_tend, &
              q_sq_buoyancy_tend, q_sq_dissip_tend, l_master_at_face, l_master_at_mass, l_boulac, turb_flux_u2, turb_flux_v2, turb_flux_w2, &
              turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_wtheta_v, dn, dnw, fnm, fnp, &
              msftx, msfty, msfux, msfuy, msfvx, msfvy, mut, c1, c2, z_at_mass, rdx, rdy, rdz, rdzw, cf1, cf2, cf3, dt, &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                                        !
      ! Purpose: Calculates RHS of prognostic TKE equation (level 2.5)                         !
      !                                                                                        !
      ! Author: Timothy W. Juliano & Pedro A. Jimenez                                          !
      !                                                                                        !
      ! Method: 1) Follows module_diffusion_em to calc shear, buoyancy, and dissipation terms  !
      !                                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      type (domain)              , intent (in) :: grid
      type (grid_config_rec_type), intent (in) :: config_flags

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: zx, zy
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)    :: du_dz, dv_dz, dw_dz, &
                            du_dx, dv_dx, dw_dx, du_dy, dv_dy, dw_dy, dthetav_dz
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out)   :: q_sq_vdiff_tend,    &
                                                                     q_sq_hdiff_tend,    &
                                                                     q_sq_shear_tend,    &
                                                                     q_sq_buoyancy_tend, &
                                                                     q_sq_dissip_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq, l_master_at_face
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: q_sq_prog
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_boulac
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: l_master_at_mass
        ! intent(in), not intent(out): only read here (by Calc_q_sq_shear* and Calc_q_sq_buoyancy);
        ! intent(out) would leave them undefined on entry, garbage for a non-contiguous actual.
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: turb_flux_u2, turb_flux_v2, turb_flux_w2, &
                                                                     turb_flux_uv, turb_flux_uw, turb_flux_vw, &
                                                                     turb_flux_wtheta_v
      real, dimension (kms:kme),                   intent (in)    :: dn, dnw, fnm, fnp
      real, dimension (ims:ime, jms:jme),          intent (in)    :: msftx, msfty, msfux, msfuy, msfvx, msfvy
      real, dimension (ims:ime, jms:jme),          intent (in)    :: mut
      real, dimension (kms:kme),                   intent (in)    :: c1, c2
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)    :: z_at_mass, rdz, rdzw
      real,                                        intent (in)    :: rdx, rdy, cf1, cf2, cf3, dt
      integer, intent (in) :: ids, ide, jds, jde, kds, kde,  &
                              ims, ime, jms, jme, kms, kme,  &
                              ips, ipe, jps, jpe, kps, kpe,  &
                              its, ite, jts, jte, kts, kte

        ! Local vars
      integer :: i, j, k, i_start, i_end, j_start, j_end, ktf
      real, dimension (its:ite, kts:kte, jts:jte) :: l_dissip
        ! slope factor for the production pairing (pbl3d_sf_pair), see Calc_q_sq_shear
      real, dimension (its-1:ite, kts:kte, jts-1:jte) :: sf_alpha_pair
      real (kind = kind(q_sq_tend)) :: N_PBL3D
      real :: q_sq_sfc, q_sq_sfc_fac
      logical :: approx_pair

      N_PBL3D = config_flags%pbl3d_nsteps

      ktf     = MIN( kte, kde-1 )
      i_start = its
      i_end   = MIN(ite,ide-1)
      j_start = jts
      j_end   = MIN(jte,jde-1)

      IF ( config_flags%open_xs .or. config_flags%specified .or. &
           config_flags%nested) i_start = MAX(ids+1,its)
      IF ( config_flags%open_xe .or. config_flags%specified .or. &
           config_flags%nested) i_end   = MIN(ide-2,ite)
      IF ( config_flags%open_ys .or. config_flags%specified .or. &
           config_flags%nested) j_start = MAX(jds+1,jts)
      IF ( config_flags%open_ye .or. config_flags%specified .or. &
           config_flags%nested) j_end   = MIN(jde-2,jte)

        !!! Diffusion !!!
      call Calc_q_sq_vertical_diffusion (N_PBL3D, q_sq_vdiff_tend, q_sq_tend, l_master_at_face, q_sq_prog, q_sq, &
          fnm, fnp, dnw, rdz, rdzw, dt, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      if ( config_flags%pbl3d_opt .gt. 1 ) then
          ! Update halo for q_sq and l_master if using full 3D model
          ! since we updated q_sq and l_master in Calc_turb_fluxes_my and
          ! need horizontal gradients for horizontal diffusion of q_sq_prog
        call Update_halo_for_hdiff (grid, config_flags, q_sq, l_master_at_face, ids, ide, jds, jde, kds, kde, &
            ims, ime, jms, jme, kms, kme, ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

        call Calc_q_sq_horizontal_diffusion (N_PBL3D, q_sq_hdiff_tend, q_sq_tend, l_master_at_face, q_sq_prog, q_sq, &
            msftx, msfty, msfux, msfvy, fnm, fnp, dn, dnw, zx, zy, rdx, rdy, rdz, rdzw, cf1, cf2, cf3, &
            ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)
      end if

        !!! Shear !!!
        ! pbl3d_sf_pair = 2 with the approximate form (pbl3d_opt = 1): the resolved flow loses kinetic
        ! energy to all nine stress components there too (Horizontal_turb_mix for the six horizontal
        ! pairings, d<w'2>/dz in Vertical_mixing_w), so q^2 is credited with the full production with
        ! the pairing of pbl3d_sf_pair = 1 instead of the vertical-shear part alone. The face stresses
        ! of Diagnose_fluxes_pbl_approx are averaged to mass points (Fill_fluxes_mass_with_fluxes_face)
        ! and the mass-point gradients are computed (Calc_q_sq_l2p5) for both forms. For pbl3d_opt = 2,
        ! 2 acts as 1.
      approx_pair = config_flags%pbl3d_opt == 1 .and. config_flags%pbl3d_sf_pair == 2
      if ( config_flags%pbl3d_opt .lt. 2 .and. .not. approx_pair ) then
        call Calc_q_sq_shear_pbl_approx (N_PBL3D, l_master_at_mass, q_sq_prog, q_sq_shear_tend, q_sq_tend, du_dz, dv_dz, turb_flux_uw, turb_flux_vw, &
            mut, c1, c2, fnm, fnp, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)
        grid%qsq_shear_h(its:ite, kts:kte, jts:jte) = 0.0   ! no horizontal production terms in the 1D approximation
      else
          ! The same slope factor Horizontal_turb_mix divides the horizontal momentum
          ! tendency by (recomputed here: it is a tile-local array there). Only read when
          ! pbl3d_sf_pair >= 1.
        call Calc_slope_factor (config_flags, msftx, msfty, grid%dx, grid%dy, zx, zy, rdzw, sf_alpha_pair, &
            ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte)
        call Calc_q_sq_shear (N_PBL3D, q_sq_shear_tend, q_sq_tend, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, &
            turb_flux_u2, turb_flux_uw, turb_flux_v2, turb_flux_vw, turb_flux_w2, turb_flux_uv, mut, c1, c2, fnm, fnp, &
            ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf, grid%qsq_shear_h, &
            sf_alpha_pair, Min (config_flags%pbl3d_sf_pair, 1))
      end if

        !!! Buoyancy !!!
      call Calc_q_sq_buoyancy (N_PBL3D, q_sq_buoyancy_tend, q_sq_tend, turb_flux_wtheta_v, dthetav_dz, q_sq_prog, l_master_at_mass, mut, c1, c2, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

        !!! Dissipation !!!
      call Fill_dissip_length_scale (config_flags%pbl3d_l_opt, l_master_at_mass, l_boulac, l_dissip, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      call Calc_q_sq_dissip (N_PBL3D, q_sq_dissip_tend, q_sq_tend, l_master_at_mass, l_dissip, q_sq_prog, mut, c1, c2, &
          ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

        ! Surface q^2 condition (pbl3d_sfc_qsq_bc >= 1; SFC_QSQ_BC in module_pbl3d_my). The
        ! closure has no lower boundary condition on q^2 (zero ground flux in
        ! Calc_q_sq_vertical_diffusion, Q_SQ_MIN floor in Fill_q_sq_with_q_sq_prog). As in the
        ! MYNN family, the lowest prognostic level is held at or above the neutral surface-layer
        ! equilibrium q^2 = B1^(2/3) u*^2 (MY82 Eq. 47b; 6.5 u*^2 for the MY82 set, B1 = 16.6),
        ! delivered as a source that closes the gap within one model step: q_sq_prog is the
        ! temporary copy q_sq_tmp, so only the tendency reaches the dynamics. Not divided by
        ! N_PBL3D on purpose: the first sub-step closes the gap, later sub-steps see none.
        ! Never reduces q^2. The energy it adds is not paid by the resolved flow and shows in
        ! the energy-closure residual diagnostic.
      if (SFC_QSQ_BC >= 1) then
        q_sq_sfc_fac = b_1 ** (2.0 / 3.0)
        do j = j_start, j_end
          do i = i_start, i_end
            q_sq_sfc = q_sq_sfc_fac * grid%ust(i, j) ** 2
            if (q_sq_prog(i, kts, j) < q_sq_sfc) then
              q_sq_tend(i, kts, j) = q_sq_tend(i, kts, j) + (c1(kts) * mut(i, j) + c2(kts)) *  &
                                     (q_sq_sfc - q_sq_prog(i, kts, j)) / dt
            end if
          end do
        end do
      end if

        !!! Bound tendency !!!
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_tend(i, k, j) = max ( q_sq_tend(i, k, j), -(c1(k) * mut(i,j) + c2(k)) * max ( 0.0 , N_PBL3D * q_sq_prog(i, k, j) ) / dt )
          end do
        end do
      end do

    end subroutine Calc_q_sq_rhs


    subroutine Calc_q_sq_vertical_diffusion (N_PBL3D, q_sq_vdiff_tend, q_sq_tend, l_master, &
              q_sq_mass, q_sq_face, fnm, fnp, dnw, rdz, rdzw, dt, ims, ime, jms, jme, kms, kme, &
              its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf             )

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !                                                                !
        ! Purpose: Calculate vertical diffusion term for prognostic TKE  !
        !          Follows MY82 Eq. 24                                   !
        !                                                                !
        ! Authors: Timothy W. Juliano & Pedro A. Jimenez                 !
        !                                                                !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_vdiff_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq_mass, q_sq_face
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master
      real, dimension (kms:kme),                   intent (in)  :: dnw, fnm, fnp
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: rdz, rdzw
      real,                                        intent (in)  :: dt
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k
      real :: Sq
      real :: q_sq_vdiff_tend_tmp
      real, dimension (its:ite, kts:kte, jts:jte) :: q_sq_vdiff_hold
      real, dimension (kms:kme) :: kq, alo, aup, bb, rr, cp, dp, qs   ! implicit branch, one column
      real :: den

        ! S_q = 0.2 (MY82) unless pbl3d_sq says otherwise; see SQ_DIFF in module_pbl3d_my.
      Sq = SQ_DIFF

      if (SQ_IMPLICIT == 1) then
          ! Implicit (backward-Euler) vertical q^2 diffusion, pbl3d_sq_implicit = 1 (2026-08-29).
          ! Same face diffusivity K = S_q l q and the same zero-flux ground and top conditions
          ! as the explicit branch below (K(kts) = K(ktf+1) = 0); q^2 at the mass levels is
          ! advanced to q* with the fluxes evaluated at q*:
          !   (q*_k - q_k)/dt = rdzw_k [ K_{k+1} rdz_{k+1} (q*_{k+1} - q*_k) - K_k rdz_k (q*_k - q*_{k-1}) ]
          ! (the explicit expression with q* on the right), a diagonally dominant tridiagonal
          ! system solved per column by the Thomas algorithm. The dynamics receives
          ! (q* - q^2)/dt as the tendency (as MYNN hands over its implicit QKE step), in the
          ! same mass-coupled form as the explicit branch. Unconditionally stable and
          ! monotone; the explicit step needs S_q l q dt/dz^2 < 1/2 (KNOWN_ISSUES E28).
        do j = j_start, j_end
          do i = i_start, i_end
            do k = kts + 1, ktf
              kq(k) = Sq * l_master(i, k, j) * Sqrt(q_sq_face(i, k, j))
            end do
            kq(kts) = 0.0
            kq(ktf + 1) = 0.0
            do k = kts, ktf
              alo(k) = dt * rdzw(i, k, j) * kq(k) * rdz(i, k, j)
              aup(k) = dt * rdzw(i, k, j) * kq(k + 1) * rdz(i, k + 1, j)
              bb(k) = 1.0 + alo(k) + aup(k)
              rr(k) = q_sq_mass(i, k, j)
            end do
            cp(kts) = - aup(kts) / bb(kts)
            dp(kts) = rr(kts) / bb(kts)
            do k = kts + 1, ktf
              den = bb(k) + alo(k) * cp(k - 1)
              cp(k) = - aup(k) / den
              dp(k) = ( rr(k) + alo(k) * dp(k - 1) ) / den
            end do
            qs(ktf) = dp(ktf)
            do k = ktf - 1, kts, -1
              qs(k) = dp(k) - cp(k) * qs(k + 1)
            end do
            do k = kts, ktf
              q_sq_vdiff_tend(i, k, j) = ( qs(k) - q_sq_mass(i, k, j) ) / dt
              q_sq_vdiff_tend_tmp = - ( G / ( dnw(k) * rdzw(i, k, j) ) ) * q_sq_vdiff_tend(i, k, j)
              q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( q_sq_vdiff_tend_tmp / N_PBL3D )
            end do
          end do
        end do
        return
      end if

      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            q_sq_vdiff_hold(i, k, j) = - ( Sq * l_master(i, k, j) * Sqrt(q_sq_face(i, k, j)) * &
                                         ( q_sq_mass(i, k, j) - q_sq_mass(i, k - 1, j) ) * rdz(i, k, j) )
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          q_sq_vdiff_hold(i, kts, j) = 0.0
          q_sq_vdiff_hold(i, ktf + 1, j) = 0.0
        end do
      end do

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_vdiff_tend(i, k, j) = - rdzw(i, k, j) * ( q_sq_vdiff_hold(i, k + 1, j) - q_sq_vdiff_hold(i, k, j) )
            q_sq_vdiff_tend_tmp = ( G / dnw(k) ) *  &
                                  ( q_sq_vdiff_hold(i, k + 1, j) - q_sq_vdiff_hold(i, k, j) )
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( q_sq_vdiff_tend_tmp / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_vertical_diffusion


    subroutine Update_halo_for_hdiff (grid, config_flags, q_sq, l_master, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, ips, ipe, jps, jpe, kps, kpe, its, ite, jts, jte, kts, kte)

      implicit none

      type (domain)              , intent (in) :: grid
      type (grid_config_rec_type), intent (in) :: config_flags
      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: q_sq, l_master
      integer,                                     intent (in)    :: ids, ide, jds, jde, kds, kde, &
                                                                     ims, ime, jms, jme, kms, kme, &
                                                                     ips, ipe, jps, jpe, kps, kpe, &
                                                                     its, ite, jts, jte, kts, kte

#ifdef DM_PARALLEL
#     include "HALO_EM_PHYS_HDIFF_PBL3D.inc"
#     include "PERIOD_BDY_EM_HDIFF_PBL3D.inc"
#endif

      call set_physical_bc3d( l_master, 'w', config_flags,   &
                              ids, ide, jds, jde, kds, kde,  &
                              ims, ime, jms, jme, kms, kme,  &
                              ips, ipe, jps, jpe, kps, kpe,  &
                              its, ite, jts, jte, kts, kte   )

      call set_physical_bc3d( q_sq, 'w', config_flags,       &
                              ids, ide, jds, jde, kds, kde,  &
                              ims, ime, jms, jme, kms, kme,  &
                              ips, ipe, jps, jpe, kps, kpe,  &
                              its, ite, jts, jte, kts, kte   )

    end subroutine Update_halo_for_hdiff


    subroutine Calc_q_sq_horizontal_diffusion (N_PBL3D, q_sq_hdiff_tend, q_sq_tend, l_master, q_sq_mass, q_sq_face, &
              msftx, msfty, msfux, msfvy, fnm, fnp, dn, dnw, zx, zy, rdx, rdy, rdz, rdzw, cf1, cf2, cf3, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_hdiff_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq_mass, q_sq_face
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master
      real, dimension (ims:ime, jms:jme),          intent (in)  :: msftx, msfty, msfux, msfvy
      real, dimension (kms:kme),                   intent (in)  :: dn, dnw, fnm, fnp
      real,                                        intent (in)  :: rdx, rdy, cf1, cf2, cf3
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: zx, zy, rdz, rdzw
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k, ktes1, ktes2
      real :: rdzu, rdzv, dz_dx, dz_dy, &
              dq_sq_dz_dz_dx, dq_sq_dz_dz_dy, mrdx, mrdy
      real :: q_sq_hdiff_tend_tmp
      real, parameter :: Sq = 0.20
      real, dimension (its-1:ite+1, kts:kte, jts-1:jte+1) :: xkxavg, q_sq_at_full_u, q_sq_at_full_v, &
           dq_sq_dx_at_u, dq_sq_dy_at_v, dq_sq_dx_at_w, dq_sq_dy_at_w, zx_at_mass, zy_at_mass

        ! Define some indexes
      ktes1 = kte - 1
      ktes2 = kte - 2

        !!! Do dq_sq/dx first !!!

         ! Interpolate q_sq from half levels to full levels (u points at faces)
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end + 1
            q_sq_at_full_u(i, k, j) = 0.5 * (fnm(k) * (q_sq_mass(i - 1, k, j) + q_sq_mass(i, k, j)) + &
                fnp(k) * (q_sq_mass(i - 1, k - 1, j) + q_sq_mass(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end + 1
          q_sq_at_full_u(i, kts, j) = 0.5 * (cf1 * q_sq_mass(i, 1, j) + cf2 * q_sq_mass(i, 2, j) + &
              cf3 * q_sq_mass(i, 3, j) + cf1 * q_sq_mass(i - 1, 1, j) +  &
              cf2 * q_sq_mass(i - 1, 2, j) + cf3 * q_sq_mass(i - 1, 3, j))
          q_sq_at_full_u(i, ktf + 1, j) = 0.5 * (q_sq_mass(i, ktes1, j) + (q_sq_mass(i, ktes1, j) - &
              q_sq_mass(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
              q_sq_mass(i - 1, ktes1, j) + (q_sq_mass(i - 1, ktes1, j) - &
              q_sq_mass(i - 1, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

        ! Calculate average eddy diffusivity at u points
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end + 1
            xkxavg(i, k, j) = Sq * 0.25 * ( l_master(i - 1, k, j) * Sqrt(q_sq_face(i - 1, k, j)) +  &
                                            l_master(i, k, j) * Sqrt(q_sq_face(i, k, j))         +  &
                                            l_master(i - 1, k + 1, j) * Sqrt(q_sq_face(i - 1, k + 1, j)) +  &
                                            l_master(i, k + 1, j) * Sqrt(q_sq_face(i, k + 1, j))         )
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end + 1
          xkxavg(i, ktf + 1, j) = xkxavg(i, ktf, j)
        end do
      end do

        ! Calculate component associated with slope in sigma surfaces (dq_sq_dz_dz_dx)
      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end + 1
              ! dz_dx = (partial z / partial x)|sigma at u points
            dz_dx = 0.5 * (zx(i, k, j) + zx(i, k + 1, j))
            rdzu = 2. / (1. / rdzw(i, k, j) + 1. / rdzw(i - 1, k, j))
              ! dq_sq_dz_dz_dx = (partial q_sq / partial z)|sigma (dq_sq_dz) *
              ! (partial z / partial x)|sigma (dz_dx)
            dq_sq_dz_dz_dx = (q_sq_at_full_u(i, k + 1, j) - q_sq_at_full_u(i, k, j)) * rdzu * dz_dx
              ! (partial q_sq / partial x)|z = msfux * (partial q_sq_at_mass / partial x)|sigma - dq_sq_dz_dz_dx)
              ! at u points
            dq_sq_dx_at_u(i, k, j) = - msfux(i, j) * xkxavg(i, k, j) *  &
                                       0.5 * ( q_sq_at_full_u(i, k + 1, j) + q_sq_at_full_u(i, k, j) ) * &
                                       (q_sq_mass(i, k, j) - q_sq_mass(i - 1, k, j)) * rdx - dq_sq_dz_dz_dx
          end do
        end do
      end do

        !!! Do dq_sq/dy second !!!

         ! Interpolate q_sq from half levels to full levels (v points at faces)
      do j = j_start, j_end + 1
        do k = kts + 1, ktf
          do i = i_start, i_end
            q_sq_at_full_v(i, k, j) = 0.5 * (fnm(k) * (q_sq_mass(i, k, j - 1) + q_sq_mass(i, k, j)) + &
                fnp(k) * (q_sq_mass(i, k - 1, j - 1) + q_sq_mass(i, k - 1, j)))
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do i = i_start, i_end
          q_sq_at_full_v(i, kts, j) = 0.5 * (cf1 * q_sq_mass(i, 1, j) + cf2 * q_sq_mass(i, 2, j) + &
              cf3 * q_sq_mass(i, 3, j) + cf1 * q_sq_mass(i, 1, j - 1) +  &
              cf2 * q_sq_mass(i, 2, j - 1) + cf3 * q_sq_mass(i, 3, j - 1))
          q_sq_at_full_v(i, ktf + 1, j) = 0.5 * (q_sq_mass(i, ktes1, j) + (q_sq_mass(i, ktes1, j) - &
              q_sq_mass(i, ktes2, j)) * 0.5 * dnw(ktes1) / dn(ktes1) + &
              q_sq_mass(i, ktes1, j - 1) + (q_sq_mass(i, ktes1, j - 1) - &
              q_sq_mass(i, ktes2, j - 1)) * 0.5 * dnw(ktes1) / dn(ktes1))
        end do
      end do

        ! Calculate average eddy diffusivity at v points
      do j = j_start, j_end + 1
        do k = kts, ktf
          do i = i_start, i_end
            xkxavg(i, k, j) = Sq * 0.25 * ( l_master(i, k, j - 1) * Sqrt(q_sq_face(i, k, j - 1)) +  &
                                            l_master(i, k, j) * Sqrt(q_sq_face(i, k, j))         +  &
                                            l_master(i, k + 1, j - 1) * Sqrt(q_sq_face(i, k + 1, j - 1)) +  &
                                            l_master(i, k + 1, j) * Sqrt(q_sq_face(i, k + 1, j))         )
          end do
        end do
      end do

      do j = j_start, j_end + 1
        do i = i_start, i_end
          xkxavg(i, ktf + 1, j) = xkxavg(i, ktf, j)
        end do
      end do

        ! Calculate component associated with slope in sigma surfaces (dq_sq_dz_dz_dy)
      do j = j_start, j_end + 1
        do k = kts, ktf
          do i = i_start, i_end
              ! dz_dx = (partial z / partial y)|sigma at y points
            dz_dy = 0.5 * (zy(i, k, j) + zy(i, k + 1, j))
            rdzv = 2. / (1. / rdzw(i, k, j) + 1. / rdzw(i, k, j - 1))
              ! dq_sq_dz_dz_dy = (partial q_sq / partial z)|sigma (dq_sq_dz) *
              ! (partial z / partial y)|sigma (dz_dy)
            dq_sq_dz_dz_dy = (q_sq_at_full_v(i, k + 1, j) - q_sq_at_full_v(i, k, j)) * rdzv * dz_dy
              ! (partial q_sq / partial y)|z = msfvy * (partial q_sq_at_mass / partial y)|sigma - dq_sq_dz_dz_dy)
              ! at v points
            dq_sq_dy_at_v(i, k, j) = - msfvy(i, j) * xkxavg(i, k, j) * &
                                       0.5 * ( q_sq_at_full_v(i, k + 1, j) + q_sq_at_full_v(i, k, j) ) * &
                                       (q_sq_mass(i, k, j) - q_sq_mass(i, k, j - 1)) * rdy - dq_sq_dz_dz_dy
          end do
        end do
      end do

        !!! Do full horizontal diffusion !!!

        ! Interpolate dq_sq_dx and dq_sq_dy to w points
      do j = j_start, j_end
        do k = kts + 1, ktf
          do i = i_start, i_end
            dq_sq_dx_at_w(i, k, j) = 0.5 * (fnm(k) * (dq_sq_dx_at_u(i + 1, k, j) + dq_sq_dx_at_u(i, k, j)) +  &
                                            fnp(k) * (dq_sq_dx_at_u(i + 1, k - 1, j) + dq_sq_dx_at_u(i, k - 1, j)))
            dq_sq_dy_at_w(i, k, j) = 0.5 * (fnm(k) * (dq_sq_dy_at_v(i, k, j + 1) + dq_sq_dy_at_v(i, k, j)) +  &
                                            fnp(k) * (dq_sq_dy_at_v(i, k - 1, j + 1) + dq_sq_dy_at_v(i, k - 1, j)))

            zx_at_mass(i, k, j) = 0.25 * (zx(i, k, j) + zx(i + 1, k, j) + zx(i, k + 1, j) + zx(i + 1, k + 1, j))
            zy_at_mass(i, k, j) = 0.25 * (zy(i, k, j) + zy(i, k, j + 1) + zy(i, k + 1, j) + zy(i, k + 1, j + 1))
          end do
        end do
      end do

      do j = j_start, j_end
        do i = i_start, i_end
          dq_sq_dx_at_w(i, kts, j) = 0.
          dq_sq_dx_at_w(i, ktf + 1, j) = 0.
          dq_sq_dy_at_w(i, kts, j) = 0.
          dq_sq_dy_at_w(i, ktf + 1,j) = 0.

          zx_at_mass(i, kts, j) = 0.25 * (zx(i, kts, j) + zx(i + 1, kts ,j) + zx(i, kts + 1, j) + zx(i + 1, kts + 1, j))
          zy_at_mass(i, kts, j) = 0.25 * (zy(i, kts, j) + zy(i, kts, j + 1) + zy(i, kts + 1, j) + zy(i, kts + 1, j + 1))
        end do
      end do

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            mrdx = msftx(i, j) * rdx
            mrdy = msfty(i, j) * rdy

            q_sq_hdiff_tend(i, k, j) = 2. * ( mrdx * (dq_sq_dx_at_u(i + 1, k, j) - dq_sq_dx_at_u(i, k, j)) + &
                                              mrdy * (dq_sq_dy_at_v(i, k, j + 1) - dq_sq_dy_at_v(i, k, j)) - &
                                              msftx(i, j) * zx_at_mass(i, k, j) * (dq_sq_dx_at_w(i, k + 1, j) - dq_sq_dx_at_w(i, k, j)) * rdzw(i, k, j) - &
                                              msfty(i, j) * zy_at_mass(i, k, j) * (dq_sq_dy_at_w(i, k + 1, j) - dq_sq_dy_at_w(i, k, j)) * rdzw(i, k, j) )
            q_sq_hdiff_tend_tmp = G / (dnw(k) * rdzw(i, k, j)) * &
                                  2. * ( mrdx * (dq_sq_dx_at_u(i + 1, k, j) - dq_sq_dx_at_u(i, k, j)) + &
                                         mrdy * (dq_sq_dy_at_v(i, k, j + 1) - dq_sq_dy_at_v(i, k, j)) - &
                                         msftx(i, j) * zx_at_mass(i, k, j) * (dq_sq_dx_at_w(i, k + 1, j) - dq_sq_dx_at_w(i, k, j)) * rdzw(i, k, j) - &
                                         msfty(i, j) * zy_at_mass(i, k, j) * (dq_sq_dy_at_w(i, k + 1, j) - dq_sq_dy_at_w(i, k, j)) * rdzw(i, k, j) )
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( q_sq_hdiff_tend_tmp / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_horizontal_diffusion


    subroutine Calc_q_sq_shear_pbl_approx (N_PBL3D, l_master, q_sq, q_sq_shear_tend, q_sq_tend, du_dz, dv_dz, turb_flux_uw, turb_flux_vw, &
              mut, c1, c2, fnm, fnp, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master, q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_shear_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: du_dz, dv_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: turb_flux_uw, &
                                                                   turb_flux_vw

      real, dimension (ims:ime, jms:jme), intent (in) :: mut
      real, dimension (kms:kme),          intent (in) :: c1, c2, fnm, fnp
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_shear_tend(i, k, j) = -2. * ( turb_flux_uw(i, k, j) * du_dz(i, k, j) +  &
                                               turb_flux_vw(i, k, j) * dv_dz(i, k, j) )
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( (c1(k) * mut(i, j) + c2(k)) * q_sq_shear_tend(i, k, j) / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_shear_pbl_approx


    subroutine Calc_q_sq_shear (N_PBL3D, q_sq_shear_tend, q_sq_tend, du_dx, du_dy, du_dz, dv_dx, dv_dy, dv_dz, dw_dx, dw_dy, dw_dz, &
              turb_flux_u2, turb_flux_uw, turb_flux_v2, turb_flux_vw, turb_flux_w2, turb_flux_uv, mut, c1, c2, fnm, fnp, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf, qsq_shear_h, &
              sf_alpha, pair)

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_shear_tend
        ! Slope factor at mass points (Calc_slope_factor) and the pairing switch
        ! (pbl3d_sf_pair). The horizontal turbulent momentum tendency is divided by
        ! sf_alpha (Calc_htend_du/dv/dw), so the kinetic energy the resolved flow actually
        ! loses to the horizontal stresses is the untapered production divided by the same
        ! factor. pair = 1 credits the q^2 budget with that amount; pair = 0 keeps the
        ! untapered production, most of which the resolved flow never pays (OPEN_ISSUES A10).
      real, dimension (its-1:ite, kts:kte, jts-1:jte), intent (in) :: sf_alpha
      integer,                                         intent (in) :: pair
        ! The six of the nine production terms that pair with the HORIZONTAL turbulent
        ! momentum tendency (u2 du/dx, uv du/dy, uv dv/dx, v2 dv/dy, uw dw/dx, vw dw/dy).
        ! Energy-closure diagnostic: that tendency is divided by the slope factor
        ! (Calc_htend_du/dv/dw) while this production is not, so the mass-weighted domain
        ! sum of ke_loss_h + qsq_shear_h / 2 measures the energy the subgrid budget is
        ! credited with that the resolved flow never paid (OPEN_ISSUES A10). History field
        ! QSQ_SHEAR_H; same sign convention as q_sq_shear_tend (twice the TKE production).
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: qsq_shear_h
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: du_dx, du_dy, du_dz,  &
                                                                   dv_dx, dv_dy, dv_dz,  &
                                                                   dw_dx, dw_dy, dw_dz
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: turb_flux_u2,         &
          turb_flux_uw, turb_flux_v2, turb_flux_vw, turb_flux_w2, turb_flux_uv

      real, dimension (ims:ime, jms:jme), intent (in) :: mut
      real, dimension (kms:kme),          intent (in) :: c1, c2, fnm, fnp
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            if (pair == 1) then
                ! Horizontal pairing credited with what the resolved flow actually pays:
                ! the six horizontal terms divided by the slope factor the momentum
                ! tendency was divided by. The three vertical terms pair with the
                ! untapered vertical mixing and are unchanged.
              qsq_shear_h(i, k, j)     = -2. / sf_alpha(i, k, j) *                       &
                                             ( turb_flux_u2(i, k, j) * du_dx(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * du_dy(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * dv_dx(i, k, j) +  &
                                               turb_flux_v2(i, k, j) * dv_dy(i, k, j) +  &
                                               turb_flux_uw(i, k, j) * dw_dx(i, k, j) +  &
                                               turb_flux_vw(i, k, j) * dw_dy(i, k, j) )
              q_sq_shear_tend(i, k, j) = -2. * ( turb_flux_uw(i, k, j) * du_dz(i, k, j) +  &
                                                 turb_flux_vw(i, k, j) * dv_dz(i, k, j) +  &
                                                 turb_flux_w2(i, k, j) * dw_dz(i, k, j) )  &
                                         + qsq_shear_h(i, k, j)
            else
                ! pre-2026-08-21 form, kept bit for bit
            q_sq_shear_tend(i, k, j) = -2. * ( turb_flux_u2(i, k, j) * du_dx(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * du_dy(i, k, j) +  &
                                               turb_flux_uw(i, k, j) * du_dz(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * dv_dx(i, k, j) +  &
                                               turb_flux_v2(i, k, j) * dv_dy(i, k, j) +  &
                                               turb_flux_vw(i, k, j) * dv_dz(i, k, j) +  &
                                               turb_flux_uw(i, k, j) * dw_dx(i, k, j) +  &
                                               turb_flux_vw(i, k, j) * dw_dy(i, k, j) +  &
                                               turb_flux_w2(i, k, j) * dw_dz(i, k, j) )
            qsq_shear_h(i, k, j)     = -2. * ( turb_flux_u2(i, k, j) * du_dx(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * du_dy(i, k, j) +  &
                                               turb_flux_uv(i, k, j) * dv_dx(i, k, j) +  &
                                               turb_flux_v2(i, k, j) * dv_dy(i, k, j) +  &
                                               turb_flux_uw(i, k, j) * dw_dx(i, k, j) +  &
                                               turb_flux_vw(i, k, j) * dw_dy(i, k, j) )
            end if
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( (c1(k) * mut(i, j) + c2(k)) * q_sq_shear_tend(i, k, j) / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_shear


    subroutine Calc_q_sq_buoyancy (N_PBL3D, q_sq_buoyancy_tend, q_sq_tend, turb_flux_wtheta_v, dthv_dz, q_sq, l_master, mut, c1, c2, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_buoyancy_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq, l_master, turb_flux_wtheta_v
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: dthv_dz

      real, dimension (ims:ime, jms:jme), intent (in) :: mut
      real, dimension (kms:kme),          intent (in) :: c1, c2
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_buoyancy_tend(i, k, j) = 2. * G_OVER_TREF * turb_flux_wtheta_v(i, k, j)
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) + ( (c1(k) * mut(i, j) + c2(k)) * q_sq_buoyancy_tend(i, k, j) / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_buoyancy


    subroutine Fill_dissip_length_scale (l_opt, l_master, l_boulac, l_dissip, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      integer,                                     intent (in)  :: l_opt
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master, l_boulac
      real, dimension (its:ite, kts:kte, jts:jte), intent (out) :: l_dissip

      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            if (l_opt == 3) then
                ! Boulac length scale is at faces
              l_dissip(i, k, j) = (l_boulac(i, k, j) + l_boulac(i, k + 1, j)) / 2.
            else
              l_dissip(i, k, j) = l_master(i, k, j)
            end if
          end do
        end do
      end do

    end subroutine Fill_dissip_length_scale


    subroutine Calc_q_sq_dissip (N_PBL3D, q_sq_dissip_tend, q_sq_tend, l_master, l_dissip, q_sq, mut, c1, c2, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, i_start, i_end, j_start, j_end, ktf)

      implicit none

      real,                                        intent (in)  :: N_PBL3D
      real, dimension (ims:ime, kms:kme, jms:jme), intent (out) :: q_sq_dissip_tend
      real, dimension (its:ite, kts:kte, jts:jte), intent (inout) :: q_sq_tend
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: q_sq
      real, dimension (ims:ime, kms:kme, jms:jme), intent (in)  :: l_master
      real, dimension (its:ite, kts:kte, jts:jte), intent (in)  :: l_dissip

      real, dimension (ims:ime, jms:jme), intent (in) :: mut
      real, dimension (kms:kme),          intent (in) :: c1, c2
      integer, intent (in) :: ims, ime, jms, jme, kms, kme,        &
                              its, ite, jts, jte, kts, kte,        &
                              i_start, i_end, j_start, j_end, ktf

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end
        do k = kts, ktf
          do i = i_start, i_end
            q_sq_dissip_tend(i, k, j) = 2. * ( q_sq(i, k, j) ** 1.5 ) /  &
                                             ( b_1 * l_dissip(i, k, j) )
            q_sq_tend(i, k, j) = q_sq_tend(i, k, j) - ( (c1(k) * mut(i, j) + c2(k)) * q_sq_dissip_tend(i, k, j) / N_PBL3D )
          end do
        end do
      end do

    end subroutine Calc_q_sq_dissip


    subroutine Calc_metric (ph, phb, rdz, rdzw, dz, z_at_mass, z_at_w, ids, ide, jds, jde, kds, kde, &
              ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, itf, jtf, ktf, i_start, i_end, j_start, j_end)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                                        !
      ! Purpose: Calculate metric terms for initialization of turbulence state !
      !                                                                        !
      ! Author: Timothy W. Juliano                                             !
      !                                                                        !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte
      integer, intent(in) :: itf, jtf, ktf, i_start, i_end, j_start, j_end

      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: ph, phb
      real, dimension(ims:ime, kms:kme, jms:jme), intent(out) :: rdz, rdzw, dz, &
                                                                 z_at_mass, z_at_w

        ! Local vars
      integer :: i, j, k

      do j = j_start, j_end

        do k = kts, kte
          do i = i_start, i_end
            z_at_w(i, k, j) = ( ph(i, k, j) + phb(i, k, j) ) / g
          end do
        end do

        do k = kts, ktf
          do i = i_start, i_end
            z_at_mass(i, k, j) = ( z_at_w(i, k + 1, j) + z_at_w(i, k, j) ) / 2.
          end do
        end do

        do k = kts, ktf
          do i = i_start, i_end
            rdzw(i, k, j) = 1.0 / ( z_at_w(i, k + 1, j) - z_at_w(i, k, j) )
            dz(i, k, j) = z_at_w(i, k + 1, j) - z_at_w(i, k, j)
          end do
        end do

        do k = kts + 1, ktf
          do i = i_start, i_end
            rdz(i, k, j) = 2.0 / ( z_at_w(i, k + 1, j) - z_at_w(i, k - 1, j) )
          end do
        end do

        do i = i_start, i_end
          rdz(i, kts, j) = 2. / (z_at_w(i, kts + 1, j) - z_at_w(i, kts, j))
        end do

      end do

    end subroutine Calc_metric


    subroutine Init_pbl3d (restart, pbl3d_opt, pbl3d_sfc_opt, pbl3d_l_opt, pbl3d_prog, pbl3d_constants, &
              pbl3d_nsteps, pbl3d_sk_eps_max, pbl3d_n_tau_max,                                                        &
              pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max,          &
              pbl3d_sq, pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar, pbl3d_sfc_qsq_zmax, l0_asym,                                &
              fnm, fnp, dnw, ph, phb, t_2, qv, thetav, alt, u, v, ust, hfx, qfx, rmol, &
              q_sq, q_sq_prog, q_sq_vdiff, q_sq_hdiff, q_sq_shear, q_sq_buoyancy, q_sq_dissip,                       &
              ids, ide, jds, jde, kds, kde, ims, ime, jms, jme, kms, kme,               &
              its, ite, jts, jte, kts, kte, l_master, l_master_at_mass, turb_flux_u2,                     &
              turb_flux_v2, turb_flux_w2, turb_flux_uv, turb_flux_uw,                   &
              turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v,                     &
              turb_flux_wtheta_v, turb_flux_theta2_v, turb_flux_utheta,                 &
              turb_flux_vtheta, turb_flux_wtheta, turb_flux_uqv,                        &
              turb_flux_vqv, turb_flux_wqv)

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !                                                      !
      ! Purpose: Initializes the PBL3D                       !
      !                                                      !
      ! Author: Pedro A. Jimenez & Timothy W. Juliano        !
      !                                                      !
      ! Method: 1) User selects set of closure constants     !
      !                                                      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      implicit none

      logical, intent(in) :: restart
      integer, intent(in) :: pbl3d_opt, pbl3d_sfc_opt, pbl3d_l_opt, pbl3d_prog, pbl3d_nsteps
      integer, intent(in) :: pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt
      real,    intent(in) :: pbl3d_sk_eps_max, pbl3d_n_tau_max, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max
      real,    intent(in) :: pbl3d_sq, pbl3d_sfc_qsq_zmax
      integer, intent(in) :: pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar
      real, dimension(ims:ime, jms:jme),          intent(inout) :: l0_asym
      character (len = *), intent(in) :: pbl3d_constants

        ! Grid vars
      real, dimension(kms:kme),                   intent(in)  :: fnm, fnp, dnw
      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: ph, phb

        ! Thermo/kinematic state vars
      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: t_2, qv, u, v, alt
      real, dimension(ims:ime, jms:jme),          intent(in)  :: ust, hfx, qfx, rmol
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: thetav

        ! Turb state vars
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: q_sq_prog, q_sq,     &
          q_sq_vdiff, q_sq_hdiff, q_sq_shear, q_sq_buoyancy, q_sq_dissip
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: l_master, l_master_at_mass, &
          turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,          &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                  &
          turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v,      &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,            &
          turb_flux_uqv, turb_flux_vqv, turb_flux_wqv

      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      call Set_init_turb_state_driver (restart, pbl3d_constants,            &
          pbl3d_nsteps, pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt,  &
          pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt,                  &
          pbl3d_sk_eps_max, pbl3d_n_tau_max, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max,                  &
          pbl3d_sq, pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar, pbl3d_sfc_qsq_zmax,                                       &
          ids, ide, jds, jde, kds, kde,                                     &
          ims, ime, jms, jme, kms, kme,                                     &
          its, ite, jts, jte, kts, kte,                                     &
          fnm, fnp, dnw, ph, phb,                                           &
          t_2, qv, thetav, alt, u, v, ust, hfx, qfx, rmol,                  &
          q_sq, q_sq_prog, q_sq_vdiff, q_sq_hdiff, q_sq_shear,              &
          q_sq_buoyancy, q_sq_dissip,                                       &
          l_master, l_master_at_mass, l0_asym,                              &
          turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,           &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                   &
          turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v,       &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,             &
          turb_flux_uqv, turb_flux_vqv, turb_flux_wqv                       )

    end subroutine Init_pbl3d


    subroutine Set_init_turb_state_driver (restart, pbl3d_constants,            &
              pbl3d_nsteps, pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt,  &
              pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt,                  &
              pbl3d_sk_eps_max, pbl3d_n_tau_max, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max,                  &
              pbl3d_sq, pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar, pbl3d_sfc_qsq_zmax,                                       &
              ids, ide, jds, jde, kds, kde,                                     &
              ims, ime, jms, jme, kms, kme,                                     &
              its, ite, jts, jte, kts, kte,                                     &
              fnm, fnp, dnw, ph, phb,                                           &
              t_2, qv, thetav, alt, u, v, ust, hfx, qfx, rmol,                  &
              q_sq, q_sq_prog, q_sq_vdiff, q_sq_hdiff, q_sq_shear,              &
              q_sq_buoyancy, q_sq_dissip,                                       &
              l_master, l_master_at_mass, l0_asym,                              &
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

      logical, intent(in) :: restart
      integer, intent(in) :: pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt, pbl3d_nsteps
      integer, intent(in) :: pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt
      real,    intent(in) :: pbl3d_sk_eps_max, pbl3d_n_tau_max, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max
      real,    intent(in) :: pbl3d_sq, pbl3d_sfc_qsq_zmax
      integer, intent(in) :: pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar
      real, dimension(ims:ime, jms:jme),          intent(inout) :: l0_asym
      character (len = *), intent(in) :: pbl3d_constants
      integer :: itf, jtf, ktf
      integer, intent(in) :: ids, ide, jds, jde, kds, kde, &
                             ims, ime, jms, jme, kms, kme, &
                             its, ite, jts, jte, kts, kte

      real, dimension (kms:kme),                  intent(in)  :: fnm, fnp, dnw
      real, dimension(ims:ime, jms:jme),          intent(in)  :: ust, hfx, qfx, rmol
      real, dimension(ims:ime, kms:kme, jms:jme), intent(in)  :: t_2, qv, u, v, &
                                                                 alt, ph, phb
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: thetav
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: q_sq_prog, q_sq,     &
          q_sq_vdiff, q_sq_hdiff, q_sq_shear, q_sq_buoyancy, q_sq_dissip
      real, dimension(ims:ime, kms:kme, jms:jme), intent(inout) :: l_master, l_master_at_mass, &
          turb_flux_u2, turb_flux_v2, turb_flux_w2, turb_flux_uv,          &
          turb_flux_uw, turb_flux_vw, turb_flux_utheta_v,                  &
          turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v,      &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta,            &
          turb_flux_uqv, turb_flux_vqv, turb_flux_wqv

        ! Local vars
      real, dimension (ims:ime, kms:kme, jms:jme) :: rdz, rdzw, z_at_mass, z_at_w, dz
      real, dimension (its:ite, kts:kte, jts:jte) :: du_dz, dv_dz, &
                                                     dthetav_dz, dqv_dz
      real, dimension (ims:ime, kms:kme, jms:jme) :: rho
      integer :: i_start, i_end, j_start, j_end

        ! Defines mass point at faces indexes
      jtf = Min (jte, jde - 1)
      itf = Min (ite, ide - 1)
      ktf = Min (kte, kde - 1)

      i_start = its
      i_end = Min (ite, ide - 1)
      j_start = jts
      j_end = Min (jte, jde - 1)

      if (.not. restart) then
          ! Calc metric terms
        call Calc_metric (ph, phb, rdz, rdzw, dz, z_at_mass, z_at_w, ids, ide, jds, jde, kds, kde, &
            ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, itf, jtf, ktf, i_start, i_end, j_start, j_end)

        call Calc_thetav (t_2, qv, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, thetav)
      end if

        ! Calc vertical derivatives
      call Calc_dvel_dz (u, 1, 0, 0, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, du_dz)

      call Calc_dvel_dz (v, 0, 0, 1, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dv_dz)

      call Calc_dmassvar_dz (thetav, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dthetav_dz)

      call Calc_dmassvar_dz (qv, rdz, ide, jde, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, dqv_dz)

        ! Call MY model to set initial state
      call Set_init_turb_state_my (restart, pbl3d_constants, pbl3d_nsteps, pbl3d_opt, pbl3d_prog, pbl3d_sfc_opt, pbl3d_l_opt, &
          pbl3d_l0_opt, pbl3d_init_opt, pbl3d_limiter_opt, pbl3d_sk_eps_max, pbl3d_n_tau_max, pbl3d_l0_min, pbl3d_dn_max, pbl3d_moist_cond_max, &
          pbl3d_sq, pbl3d_sfc_qsq_bc, pbl3d_sq_implicit, pbl3d_t2_scalar, pbl3d_sfc_qsq_zmax, ids, ide, &
          jds, jde, kds, kde, ims, ime, jms, jme, kms, kme, its, ite, jts, jte, kts, kte, itf, jtf, ktf, i_start, i_end, j_start, j_end, &
          fnm, fnp, dnw, ph, phb, rdzw, z_at_mass, dz, t_2, qv, alt, u, v, ust, hfx, qfx, rmol, rho, du_dz, dv_dz, dthetav_dz, dqv_dz, &
          q_sq, q_sq_prog, q_sq_vdiff, q_sq_hdiff, q_sq_shear, q_sq_buoyancy, q_sq_dissip, l_master, l_master_at_mass, l0_asym, turb_flux_u2, turb_flux_v2, &
          turb_flux_w2, turb_flux_uv, turb_flux_uw, turb_flux_vw, turb_flux_utheta_v, turb_flux_vtheta_v, turb_flux_wtheta_v, turb_flux_theta2_v, &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_wtheta, turb_flux_uqv, turb_flux_vqv, turb_flux_wqv)

    end subroutine Set_init_turb_state_driver


    subroutine Populate_wrflux_sgs_from_pbl3d (config_flags, rho, fnm, fnp, &
        turb_flux_wtheta, turb_flux_wtheta_v, turb_flux_wqv, turb_flux_uw, turb_flux_vw, turb_flux_w2, &
        turb_flux_utheta, turb_flux_vtheta, turb_flux_utheta_v, turb_flux_vtheta_v, &
        turb_flux_uqv, turb_flux_vqv, turb_flux_u2, turb_flux_v2, turb_flux_uv, &
        ftz_sgs, fqz_sgs, fuz_sgs, fvz_sgs, fwz_sgs, &
        ftx_sgs, fty_sgs, fqx_sgs, fqy_sgs, fux_sgs, fvx_sgs, fvy_sgs, fwx_sgs, fwy_sgs, &
        ids, ide, jds, jde, kds, kde, &
        ims, ime, jms, jme, kms, kme, &
        its, ite, jts, jte, kts, kte)

      ! Populates WRFlux's SGS flux state arrays (ftz_sgs/fqz_sgs/fuz_sgs/fvz_sgs/fwz_sgs and their
      ! horizontal counterparts ftx_sgs/fty_sgs/fqx_sgs/fqy_sgs/fux_sgs/fvx_sgs/fvy_sgs/fwx_sgs/fwy_sgs)
      ! directly from the 3D PBL scheme's own native kinematic turbulent flux diagnostics. WRFlux's
      ! generic mechanisms for these (fluxes_from_bl_tend in module_pbl_driver.F,
      ! vertical_diffusion_implicit and horizontal_diffusion_2 in module_diffusion_em.F) are all gated
      ! off whenever pbl3d_opt is active, since pbl3d bypasses the standard PBL/km_opt=5 tendency and
      ! diff_opt=1/2 diffusion paths entirely. Converts pbl3d's kinematic fluxes (K m/s, m2/s2, ...) to
      ! WRFlux's dynamic (density-weighted) flux convention (rho * kinematic flux), matching the units
      ! WRFlux declares for these arrays.
      !
      ! rho (rho_tmp) is mass-point/unstaggered. All of pbl3d's turb_flux_* diagnostics are Z-staggered
      ! (w-levels) regardless of whether the component is conceptually a "horizontal" or "vertical"
      ! flux (pbl3d computes its whole Level-2.5 closure on one common vertical grid). WRFlux's arrays
      ! are staggered per Arakawa-C convention instead: ftz_sgs/fqz_sgs/fwz_sgs stay Z-staggered like
      ! their pbl3d source, so only rho needs interpolating to w-levels (via fnm/fnp, mirroring
      ! module_diffusion_em.F's xkxavg); ftx_sgs/fty_sgs/fqx_sgs/fqy_sgs/fux_sgs/fvx_sgs/fvy_sgs are
      ! mass-level in Z, so the corresponding pbl3d flux is first de-staggered down from w-levels via a
      ! simple two-point vertical average. fwx_sgs/fwy_sgs are the same physical stress component as
      ! fuz_sgs/fvz_sgs (u'w'/v'w' appearing in the w-momentum equation's horizontal-flux-divergence
      ! term rather than the u/v-momentum equation's vertical one) and reuse those exact values.
      ! Momentum fluxes are additionally staggered horizontally via the same two-point (u/v points) or
      ! four-point (uv corner point) averaging vertical_diffusion_implicit/horizontal_diffusion_2 use
      ! for xkxavg/muavg_u/rho at those same points.

      use module_configure, only : grid_config_rec_type

      implicit none

      type (grid_config_rec_type), intent (in) :: config_flags

      integer, intent (in) :: ids, ide, jds, jde, kds, kde, &
                              ims, ime, jms, jme, kms, kme, &
                              its, ite, jts, jte, kts, kte

      real, dimension (kms:kme), intent (in) :: fnm, fnp

      real, dimension (ims:ime, kms:kme, jms:jme), intent (in) :: rho, &
          turb_flux_wtheta, turb_flux_wtheta_v, turb_flux_wqv, turb_flux_uw, turb_flux_vw, turb_flux_w2, &
          turb_flux_utheta, turb_flux_vtheta, turb_flux_utheta_v, turb_flux_vtheta_v, &
          turb_flux_uqv, turb_flux_vqv, turb_flux_u2, turb_flux_v2, turb_flux_uv

      real, dimension (ims:ime, kms:kme, jms:jme), intent (inout) :: ftz_sgs, fqz_sgs, fuz_sgs, fvz_sgs, fwz_sgs, &
          ftx_sgs, fty_sgs, fqx_sgs, fqy_sgs, fux_sgs, fvx_sgs, fvy_sgs, fwx_sgs, fwy_sgs

      integer :: i, j, k, ktf
      real, dimension (ims:ime, kms:kme, jms:jme) :: rho_w
      real, dimension (ims:ime, kms:kme, jms:jme) :: u2_mass, v2_mass

      ktf = min(kte, kde-1)

      ! Interpolate mass-point rho onto w-levels; surface (k=kts) keeps the mass-level value
      do j = jts, min(jte, jde-1)
      do i = its, min(ite, ide-1)
        rho_w(i,kts,j) = rho(i,kts,j)
      end do
      end do
      do j = jts, min(jte, jde-1)
      do k = kts+1, ktf
      do i = its, min(ite, ide-1)
        rho_w(i,k,j) = fnm(k)*rho(i,k,j) + fnp(k)*rho(i,k-1,j)
      end do
      end do
      end do

      ! De-stagger pbl3d's Z-staggered (w-level) u2/v2 diagnostics down to mass levels via a simple
      ! two-point vertical average (fux_sgs/fvy_sgs are mass-level in Z, unlike ftz_sgs/fqz_sgs/fwz_sgs
      ! above). Safe as a precomputed tile-local array since fux_sgs/fvy_sgs read it at the same (i,j)
      ! only, with no horizontal neighbor offset - unlike utheta/vtheta/uqv/vqv/uv below, which need an
      ! i-1 or j-1 neighbor and are therefore computed inline directly from the grid-level (halo-safe)
      ! turb_flux_* arrays instead of via a tile-local intermediate (a tile-local array only has its
      ! own tile's index range populated, so reading a neighboring tile's index from it would be
      ! uninitialized memory).
      if (config_flags%output_usgs_fluxes .or. config_flags%output_vsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          u2_mass(i,k,j) = 0.5*(turb_flux_u2(i,k,j) + turb_flux_u2(i,k+1,j))
          v2_mass(i,k,j) = 0.5*(turb_flux_v2(i,k,j) + turb_flux_v2(i,k+1,j))
        end do
        end do
        end do
      end if

      if (config_flags%output_tsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          if (config_flags%output_dry_theta_fluxes) then
            ftz_sgs(i,k,j) = rho_w(i,k,j) * turb_flux_wtheta(i,k,j)
          else
            ftz_sgs(i,k,j) = rho_w(i,k,j) * turb_flux_wtheta_v(i,k,j)
          end if
        end do
        end do
        end do
      end if

      if (config_flags%output_qsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fqz_sgs(i,k,j) = rho_w(i,k,j) * turb_flux_wqv(i,k,j)
        end do
        end do
        end do
      end if

      if (config_flags%output_usgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, ite
          fuz_sgs(i,k,j) = 0.5*(rho_w(i,k,j)+rho_w(i-1,k,j)) * 0.5*(turb_flux_uw(i,k,j)+turb_flux_uw(i-1,k,j))
        end do
        end do
        end do
      end if

      if (config_flags%output_vsgs_fluxes) then
        do j = jts, jte
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fvz_sgs(i,k,j) = 0.5*(rho_w(i,k,j)+rho_w(i,k,j-1)) * 0.5*(turb_flux_vw(i,k,j)+turb_flux_vw(i,k,j-1))
        end do
        end do
        end do
      end if

      if (config_flags%output_wsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fwz_sgs(i,k,j) = rho_w(i,k,j) * turb_flux_w2(i,k,j)
        end do
        end do
        end do
      end if

      ! Horizontal SGS fluxes (mass-level in Z; module_first_rk_step_part2.F skips the whole
      ! horizontal_diffusion_2 call, which would otherwise populate these, whenever pbl3d_opt>0)
      if (config_flags%output_tsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, ite
          if (config_flags%output_dry_theta_fluxes) then
            ftx_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i-1,k,j)) * 0.25*( &
                turb_flux_utheta(i,k,j) + turb_flux_utheta(i,k+1,j) + &
                turb_flux_utheta(i-1,k,j) + turb_flux_utheta(i-1,k+1,j) )
          else
            ftx_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i-1,k,j)) * 0.25*( &
                turb_flux_utheta_v(i,k,j) + turb_flux_utheta_v(i,k+1,j) + &
                turb_flux_utheta_v(i-1,k,j) + turb_flux_utheta_v(i-1,k+1,j) )
          end if
        end do
        end do
        end do
        do j = jts, jte
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          if (config_flags%output_dry_theta_fluxes) then
            fty_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i,k,j-1)) * 0.25*( &
                turb_flux_vtheta(i,k,j) + turb_flux_vtheta(i,k+1,j) + &
                turb_flux_vtheta(i,k,j-1) + turb_flux_vtheta(i,k+1,j-1) )
          else
            fty_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i,k,j-1)) * 0.25*( &
                turb_flux_vtheta_v(i,k,j) + turb_flux_vtheta_v(i,k+1,j) + &
                turb_flux_vtheta_v(i,k,j-1) + turb_flux_vtheta_v(i,k+1,j-1) )
          end if
        end do
        end do
        end do
      end if

      if (config_flags%output_qsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, ite
          fqx_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i-1,k,j)) * 0.25*( &
              turb_flux_uqv(i,k,j) + turb_flux_uqv(i,k+1,j) + &
              turb_flux_uqv(i-1,k,j) + turb_flux_uqv(i-1,k+1,j) )
        end do
        end do
        end do
        do j = jts, jte
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fqy_sgs(i,k,j) = 0.5*(rho(i,k,j)+rho(i,k,j-1)) * 0.25*( &
              turb_flux_vqv(i,k,j) + turb_flux_vqv(i,k+1,j) + &
              turb_flux_vqv(i,k,j-1) + turb_flux_vqv(i,k+1,j-1) )
        end do
        end do
        end do
      end if

      if (config_flags%output_usgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fux_sgs(i,k,j) = rho(i,k,j) * u2_mass(i,k,j)
        end do
        end do
        end do
      end if

      if (config_flags%output_vsgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fvy_sgs(i,k,j) = rho(i,k,j) * v2_mass(i,k,j)
        end do
        end do
        end do
      end if

      if (config_flags%output_usgs_fluxes .or. config_flags%output_vsgs_fluxes) then
        do j = jts, jte
        do k = kts, ktf
        do i = its, ite
          fvx_sgs(i,k,j) = 0.25*(rho(i-1,k,j)+rho(i,k,j)+rho(i-1,k,j-1)+rho(i,k,j-1)) * 0.125*( &
              turb_flux_uv(i,  k,j  ) + turb_flux_uv(i,  k+1,j  ) + &
              turb_flux_uv(i-1,k,j  ) + turb_flux_uv(i-1,k+1,j  ) + &
              turb_flux_uv(i,  k,j-1) + turb_flux_uv(i,  k+1,j-1) + &
              turb_flux_uv(i-1,k,j-1) + turb_flux_uv(i-1,k+1,j-1) )
        end do
        end do
        end do
      end if

      ! fwx_sgs/fwy_sgs are the same physical stress component as fuz_sgs/fvz_sgs (u'w'/v'w'), just
      ! appearing in the w-momentum equation's horizontal-flux-divergence term instead of the
      ! u/v-momentum equation's vertical one - reuse the values computed above directly.
      if (config_flags%output_wsgs_fluxes .and. config_flags%output_usgs_fluxes) then
        do j = jts, min(jte, jde-1)
        do k = kts, ktf
        do i = its, ite
          fwx_sgs(i,k,j) = fuz_sgs(i,k,j)
        end do
        end do
        end do
      end if

      if (config_flags%output_wsgs_fluxes .and. config_flags%output_vsgs_fluxes) then
        do j = jts, jte
        do k = kts, ktf
        do i = its, min(ite, ide-1)
          fwy_sgs(i,k,j) = fvz_sgs(i,k,j)
        end do
        end do
        end do
      end if

    end subroutine Populate_wrflux_sgs_from_pbl3d

  end module module_pbl3d
