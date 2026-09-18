#!/usr/bin/env python
"""Cross-range (meridional) forcing over the northern range, ICON (met_em native levels) vs WRF runs, hourly.
Boxes (lon 11.30-11.85E): FORE 47.70-47.90N, KARW 47.45-47.58N, RANGE 47.30-47.42N, INN 47.24-47.30N. Pressure at FIXED heights ASL (log-p per column, only columns above
ground, box means); PGF_y = -(1/rho) dp/dy between box centres, NEGATIVE = pushes air southward (drives the northerly); units 1e-4 m/s2. Also box-mean theta 1500-2500 m ASL
and the mean v in 1500-2500 m ASL (the layer that crosses the crest). Usage: python cross_range_forcing_icon_vs_wrf.py RUN[=SEGS]... [DAY=17] [HOURS=13,14,15,16,17]"""
import glob, sys, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D="/gpfs/data/fs72996/ewahl"; A=sys.argv[1:]; DAY=next((a[4:] for a in A if a.startswith("DAY=")),"17"); HOURS=[int(x) for x in next((a[6:] for a in A if a.startswith("HOURS=")),"13,14,15,16,17").split(",")]
R={}
for a in [a for a in A if "=" not in a or a.split("=")[0] not in ("DAY","HOURS")] or ["X17=X17a+X17b"]:
    lab,_,segs=a.partition("="); R[lab]={f.split("d01_")[1][:16]:f for s in (segs.split("+") if segs else [lab]) for f in glob.glob(f"{D}/exp/{s}/wrf_output/*/wrfout_d01_*.nc")}
ZF=np.array([1500.,2000.,2500.,3000.]); RHO=np.array([1.04,0.99,0.94,0.89])
def p_at_z(z3,p3,zf):
    out=np.full((len(zf),)+z3.shape[1:],np.nan)
    for k,z in enumerate(zf):
        ab=z3>=z; kk=np.argmax(ab,0); ok=ab.any(0)&(kk>0); j,i=np.where(ok); k1=kk[ok]; k0=k1-1
        out[k,j,i]=np.exp(np.log(p3[k0,j,i])+(z-z3[k0,j,i])/(z3[k1,j,i]-z3[k0,j,i])*(np.log(p3[k1,j,i])-np.log(p3[k0,j,i])))
    return out
def wrf(f):
    d=nc.Dataset(f); ph=(np.asarray(d["PH"][0])+np.asarray(d["PHB"][0]))/9.81; z=0.5*(ph[:-1]+ph[1:]); p=np.asarray(d["P"][0])+np.asarray(d["PB"][0]); U,V=np.asarray(d["U"][0]),np.asarray(d["V"][0]); u=0.5*(U[:,:,:-1]+U[:,:,1:]); v=0.5*(V[:,:-1]+V[:,1:]); ca,sa=np.asarray(d["COSALPHA"][0]),np.asarray(d["SINALPHA"][0]); th=np.asarray(d["T"][0])+300; la,lo=np.asarray(d["XLAT"][0]),np.asarray(d["XLONG"][0]); d.close(); return la,lo,z,p,v*ca+u*sa,th
def icon(f):
    d=nc.Dataset(f); z=np.asarray(d["GHT"][0]); p=np.asarray(d["PRES"][0]); T=np.asarray(d["TT"][0]); U,V=np.asarray(d["UU"][0]),np.asarray(d["VV"][0]); v=0.5*(V[:,:-1]+V[:,1:]); la,lo=np.asarray(d["XLAT_M"][0]),np.asarray(d["XLONG_M"][0]); d.close(); o=np.argsort(z[:,0,0]); return la,lo,z[o][1:],p[o][1:],v[o][1:],(T*(1e5/p)**0.2854)[o][1:]
BOX={"FORE":(47.70,47.90),"KARW":(47.45,47.58),"RANGE":(47.30,47.42),"INN":(47.24,47.30)}; yc={k:0.5*(a+b) for k,(a,b) in BOX.items()}
print("PGF_y [1e-4 m/s2], negative = southward push (drives the northerly); pairs FORE->KARW, KARW->RANGE, RANGE->INN at z = "+", ".join(f"{int(z)}" for z in ZF)+" m ASL (nan = box below ground at that height); th = theta 1500-2500 m ASL [K]; v = mean meridional wind 1500-2500 m ASL [m/s]")
for h in HOURS:
    items=[("ICON",icon(f"{D}/WPS/metgrid_output_1712nat/met_em.d01.2025-07-{DAY}_{h:02d}:00:00.nc"))]+[(k,wrf(R[k][f"2025-07-{DAY}_{h:02d}:00"])) for k in R if f"2025-07-{DAY}_{h:02d}:00" in R[k]]
    for name,(la,lo,z,p,v,th) in items:
        pz=p_at_z(z,p,ZF); lonb=(lo>11.30)&(lo<11.85); M={k:lonb&(la>a)&(la<b) for k,(a,b) in BOX.items()}
        pm={k:np.array([np.nanmean(pz[i][m]) if np.isfinite(pz[i][m]).sum()>0.3*m.sum() else np.nan for i in range(len(ZF))]) for k,m in M.items()}
        def pg(a,b): return -(pm[b]-pm[a])/((yc[b]-yc[a])*111e3)/RHO*1e4   # b is south of a: dy negative handled by sign of (yc[b]-yc[a])
        lay=lambda x,m:(lambda w:float(np.where(w,x[:,m],0).sum()/max(w.sum(),1)))((z[:,m]>=1500)&(z[:,m]<2500))
        row=f"{h:02d} {name:6s}| "+" | ".join(f"{a[:4]}>{b[:4]} "+" ".join(f"{x:+6.2f}" for x in pg(a,b)) for a,b in (("FORE","KARW"),("KARW","RANGE"),("RANGE","INN")))
        row+=" | th "+" ".join(f"{k[:4]} {lay(th,m):6.2f}" for k,m in M.items())+" | v "+" ".join(f"{lay(v,m):+5.1f}" for m in M.values()); print(row)
