!testdpotr_test_gh_2691.f90
subroutine garbage(okflag)
     implicit none
     integer, intent(out) :: okflag
     double precision, dimension(3,3) :: a, a2
     integer, parameter :: lwork = 100
     double precision, dimension(lwork) :: work(lwork)
     integer, dimension(3) :: ipiv
     integer :: info, i, j

     okflag = 1

     ! condition number =~ 19, well invertible
     a(1,1) = 0.68534241
     a(1,2) = 0.63723771
     a(2,1) = 0.63723771
     a(1,3) = 0.37423535
     a(3,1) = 0.37423535
     a(2,2) = 2.42926786
     a(2,3) = 2.33541214
     a(3,2) = 2.33541214
     a(3,3) = 3.30327538

     a2 = a

     call dpotrf('L', 3, a, 3, info)
     if (info.ne.0) then
         okflag = 0
         write(*,*) 'DPOTRF failed'
         return
     end if
     do i = 1, 3
         do j = 1, i
             write(*,*) 'DPOTRF result', i, j, a(i,j)
         end do
     end do
     do i = 1, 3
         do j = i+1, 3
             a(i,j) = 0
         end do
     end do
     call dpotri('L', 3, a, 3, info)
     if (info.ne.0) then
         okflag = 0
         write(*,*) 'DPOTRI failed'
         return
     end if

     call dgetrf(3, 3, a2, 3, ipiv, info)
     if (info.ne.0) then
         okflag = 0
         write(*,*) 'DGETRF failed'
         return
     end if
     call dgetri(3, a2, 3, ipiv, work, lwork, info)
     if (info.ne.0) then
         okflag = 0
         write(*,*) 'DGETRI failed'
         return
     end if
     do i = 1, 3
         do j = 1, i
             write(*,*) i, j, a(i,j), a2(i,j)
             if (abs(a(i,j) - a2(i,j)) > 1e-3 + 1e-3*abs(a(i,j))) then
                okflag = 0
                write(*,*) '# po/ge mismatch!'
             end if
         end do
     end do
end subroutine

program main
     integer :: okflag
     call garbage(okflag)
     if (okflag.eq.1) then
         write(*,*) 'OK'
     else
         write(*,*) 'FAIL'
     end if
end program
