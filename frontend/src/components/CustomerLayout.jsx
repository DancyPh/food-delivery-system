import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { supabase } from '../lib/supabase'

const MENU_ITEMS = [
  { label: 'Trang chủ', path: '/customer', icon: '🏠' },
  { label: 'Giỏ hàng', path: '/customer/cart', icon: '🛒' },
  { label: 'Đơn hàng', path: '/customer/orders', icon: '📋' },
  { label: 'Địa chỉ', path: '/customer/addresses', icon: '📍' },
  { label: 'Cá nhân', path: '/customer/profile', icon: '👤' },
]

export default function CustomerLayout({ children }) {
  const { profile } = useAuth()
  const location = useLocation()

  async function handleLogout() {
    await supabase.auth.signOut()
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      {/* Header trên cùng */}
      <header className="bg-white shadow-sm sticky top-0 z-20">
        <div className="px-4 py-4 flex items-center justify-between">
          <h1 className="text-xl font-bold text-orange-500">FoodDelivery</h1>
          <div className="flex items-center gap-4">
            <span className="text-gray-600 text-sm hidden sm:inline">
              Xin chào, {profile?.full_name}
            </span>
            <button onClick={handleLogout} className="text-sm text-red-500 hover:underline">
              Đăng xuất
            </button>
          </div>
        </div>
      </header>

      <div className="flex flex-1">
        {/* Sidebar bên trái */}
        <aside className="w-56 bg-white border-r hidden md:block">
          <nav className="p-4 space-y-1">
            {MENU_ITEMS.map((item) => {
              const isActive = location.pathname === item.path
              return (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`flex items-center gap-3 px-3 py-2 rounded-md text-sm transition ${
                    isActive
                      ? 'bg-orange-50 text-orange-600 font-medium'
                      : 'text-gray-600 hover:bg-gray-100'
                  }`}
                >
                  <span>{item.icon}</span>
                  <span>{item.label}</span>
                </Link>
              )
            })}
          </nav>
        </aside>

        {/* Nội dung chính */}
        <main className="flex-1 min-w-0">{children}</main>
      </div>
    </div>
  )
}