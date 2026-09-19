#!/usr/bin/env python
"""Validation of the binary rebuilt 2026-09-18 (pbl3d_l_opt=5, pbl3d_dn_max). (1) BB5def (defaults) 13:05 frame vs X22's: every variable must be bit-identical.
(2) BB5new (l_opt=5, dn_max=0.4): all fields finite; master length and q_sq statistics vs BB5def; diffusion number q l dt / (2 dz^2)."""
import glob, numpy as np, netCDF4 as nc
D="/gpfs/data/fs72996/ewahl"
def fr(run,t): 
    f=glob.glob(f"{D}/exp/{run}/wrf_output/*/wrfout_d01_2025-07-17_{t}:00.nc")+glob.glob(f"{D}/exp/{run}/temp/branko/wrfout_d01_2025-07-17_{t}:00.nc"); return f[0] if f else None
a,b=fr("X22","13:05"),fr("BB5def","13:05"); print("reference",a,"\ntest     ",b)
A,B=nc.Dataset(a),nc.Dataset(b); nd=0; nv=0; worst=[]
for v in A.variables:
    if v not in B.variables: print("missing in test:",v); nd+=1; continue
    x,y=A[v][:],B[v][:]; nv+=1
    if x.dtype.kind in "SU": continue
    x,y=np.ma.filled(x,0),np.ma.filled(y,0)
    if not np.array_equal(x,y,equal_nan=True): nd+=1; worst.append((v,float(np.nanmax(np.abs(x.astype('f8')-y.astype('f8'))))))
print(f"(1) variables compared {nv}, differing {nd}", "-> BIT-IDENTICAL" if nd==0 else f"-> DIFFERENT: {sorted(worst,key=lambda t:-t[1])[:8]}")
new=[v for v in B.variables if v not in A.variables]; print("    variables only in the new binary's output:",new)
c=fr("BB5new","13:05")
if c:
    C=nc.Dataset(c); bad=[v for v in C.variables if C[v].dtype.kind=="f" and not np.isfinite(np.ma.filled(C[v][:],0)).all()]; print(f"(2) BB5new non-finite fields: {bad if bad else 'none'}")
    hg=np.asarray(C["HGT"][0]); ph=(np.asarray(C["PH"][0])+np.asarray(C["PHB"][0]))/9.81; dzw=np.diff(ph,axis=0); agl=ph[:-1]-hg[None]
    for name,ds in (("BB5def",B),("BB5new",C)):
        lm=[v for v in ("L_MASTER","EL_PBL") if v in ds.variables and float(np.abs(ds[v][0]).max())>0]; q=np.sqrt(np.maximum(np.asarray(ds["Q_SQ"][0]),0)); l0=np.asarray(ds["L0_ASYM"][0]) if "L0_ASYM" in ds.variables else None
        row=f"    {name}: l0 p10/50/90 {np.percentile(l0,10):.0f}/{np.percentile(l0,50):.0f}/{np.percentile(l0,90):.0f} m; q_sq p50/p99 (k<12) {np.percentile(q[:12]**2,50):.2f}/{np.percentile(q[:12]**2,99):.2f}"
        if lm:
            l=np.asarray(ds[lm[0]][0]); n=min(l.shape[0],dzw.shape[0]); dzm=np.minimum(dzw[1:n],dzw[:n-1]); dn=0.5*q[1:n]*l[1:n]*2.0/dzm**2
            row+=f"; {lm[0]} (k<12) p50/p99 {np.percentile(l[1:12],50):.1f}/{np.percentile(l[1:12],99):.1f} m, at 150-400 m AGL p50 {np.median(l[:n][(agl[:n]>=150)&(agl[:n]<400)]):.1f} m; diffusion number max {dn[:11].max():.2f}, cells>0.5 in lowest 12: {(dn[:11]>0.5).sum()}"
        print(row)
    print("    max |V| first level BB5new:",float(np.abs(np.asarray(C['V'][0,0])).max()),"m/s;  UST max",float(np.asarray(C['UST'][0]).max()))
