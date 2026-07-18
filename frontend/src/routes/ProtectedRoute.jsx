import { Navigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export default function ProtectedRoute({ children, allowedRoles }) {
  const { user, profile, loading } = useAuth()

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        Đang tải...
      </div>
    )
  }

  // Chưa đăng nhập -> về trang login
  if (!user) {
    return <Navigate to="/login" replace />
  }

  // Đã đăng nhập nhưng profile chưa load xong (hiếm khi xảy ra, phòng hờ)
  if (!profile) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        Đang tải thông tin tài khoản...
      </div>
    )
  }

  // Có giới hạn role, nhưng role hiện tại không nằm trong danh sách cho phép
  if (allowedRoles && !allowedRoles.includes(profile.role)) {
    return <Navigate to="/" replace />
  }

  return children
}