import { useAuth } from '../../contexts/AuthContext'
import { supabase } from '../../lib/supabase'

export default function RestaurantHome() {
  const { profile } = useAuth()

  async function handleLogout() {
    await supabase.auth.signOut()
  }

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold">Trang quản lý nhà hàng</h1>
      <p className="text-gray-600">Xin chào, {profile?.full_name}</p>
      <button onClick={handleLogout} className="mt-4 bg-red-500 text-white px-4 py-2 rounded">
        Đăng xuất
      </button>
    </div>
  )
}