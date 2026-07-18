import { Navigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

// Bảng ánh xạ role -> trang chủ tương ứng
const ROLE_HOME_PATH = {
  customer: '/customer',
  restaurant: '/restaurant',
  rider: '/rider',
  admin: '/admin',
}

export default function RoleRedirect() {
  const { profile, loading } = useAuth()

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        Đang tải...
      </div>
    )
  }

  const targetPath = ROLE_HOME_PATH[profile?.role] ?? '/login'
  return <Navigate to={targetPath} replace />
}