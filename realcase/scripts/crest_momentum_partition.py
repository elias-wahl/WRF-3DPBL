#!/usr/bin/env python
"""Who carries the vertical momentum flux over the crests: the RESOLVED eddies or the closure?
Resolved flux from deviations of v and w about a local BOX mean (side ~BOX km, so terrain-following stationary
structure larger than the box stays in the mean), at fixed heights above ground, zone mean over the crest cells;
subgrid flux from the closure's VW_SGS_MEAN (30-min mean file). Positive = northerly momentum carried DOWNWARD.
Usage: python crest_momentum_partition.py RUN [RUN ...] [T=14:00]"""
import sys, glob, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D="/gpfs/data/fs72996/ewahl"; A=[a for a in sys.argv[1:] if not a.startswith("T=")]; T=next((a[2:] for a in sys.argv[1:] if a.startswith("T=")),"14:00"); BOX=11
HS=(25,50,100,150,250,400,600,900,1300)
def zone(la,lo,hg): return (lo>11.30)&(lo<11.85)&(la>47.27)&(la<47.42)&(hg>1800)
def boxmean(x,n):
    k=np.ones(n)/n; import scipy.ndimage as ndi
    return ndi.uniform_filter(x,size=(1,n,n),mode="nearest")
print(f"vertical flux of meridional momentum over the crest cells at {T} UT, m2/s2; positive = NORTHERLY momentum carried DOWN.")
print(f"resolved = <v'w'> with v',w' the deviation from a {BOX}x{BOX}-cell ({BOX*0.5:.1f} km) box mean at fixed height AGL; subgrid = closure's VW_SGS_MEAN (30-min mean ending at {T}).")
print(f"{'run':6s} {'kind':9s} "+" ".join(f"{h:>7d}" for h in HS))
for run in A:
    f=glob.glob(f"{D}/exp/{run}/wrf_output/*/wrfout_d01_2025-07-17_{T}:00.nc")
    if not f: print(run,"no frame"); continue
    d=nc.Dataset(f[0]); la,lo,hg=[np.asarray(d[k][0]) for k in ("XLAT","XLONG","HGT")]; m=zone(la,lo,hg)
    ph=(np.asarray(d["PH"][0])+np.asarray(d["PHB"][0]))/9.81; z=0.5*(ph[:-1]+ph[1:])
    V=np.asarray(d["V"][0]); v=0.5*(V[:,:-1]+V[:,1:]); W=np.asarray(d["W"][0]); w=0.5*(W[:-1]+W[1:]); U=np.asarray(d["U"][0]); u=0.5*(U[:,:,:-1]+U[:,:,1:])
    ca,sa=np.asarray(d["COSALPHA"][0]),np.asarray(d["SINALPHA"][0]); ve=v*ca+u*sa; d.close()
    agl=z-hg[None]
    res=[]
    for h in HS:
        vv=np.array([np.array([np.interp(h,agl[:,j,i],ve[:,j,i]) for i in range(la.shape[1])]) for j in range(la.shape[0])])
        ww=np.array([np.array([np.interp(h,agl[:,j,i],w[:,j,i]) for i in range(la.shape[1])]) for j in range(la.shape[0])])
        vp=vv-boxmean(vv[None],BOX)[0]; wp=ww-boxmean(ww[None],BOX)[0]
        res.append(-float(np.mean((vp*wp)[m])))   # <v'w'> ; sign flip so positive = northerly momentum downward
    print(f"{run:6s} {'resolved':9s} "+" ".join(f"{x:7.3f}" for x in res))
    mf=glob.glob(f"{D}/exp/{run}/wrf_output/*/meanout_d01_2025-07-17_{T}:00.nc")
    if mf:
        dm=nc.Dataset(mf[0]); F=np.asarray(dm["VW_SGS_MEAN"][0])[:,m]; zw=np.asarray(dm["Z_MEAN"][0])[:,m]-hg[m][None]; dm.close()
        sg=[float(np.mean([np.interp(h,zw[:,c],F[:,c]) for c in range(F.shape[1])])) for h in HS]
        print(f"{'':6s} {'subgrid':9s} "+" ".join(f"{x:7.3f}" for x in sg))
        print(f"{'':6s} {'res share':9s} "+" ".join(f"{abs(r)/max(abs(r)+abs(s),1e-9)*100:6.0f}%" for r,s in zip(res,sg)))
