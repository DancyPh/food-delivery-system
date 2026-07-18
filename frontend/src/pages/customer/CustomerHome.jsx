import { useEffect, useState, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import RestaurantCard from '../../components/RestaurantCard'
import CustomerLayout from '../../components/CustomerLayout'

export default function CustomerHome() {
  const [restaurants, setRestaurants] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const [searchTerm, setSearchTerm] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [sortBy, setSortBy] = useState('newest')

  useEffect(() => {
    fetchRestaurants()
  }, [])

  async function fetchRestaurants() {
    setLoading(true)
    setError('')

    const { data, error } = await supabase
      .from('restaurants')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      setError(error.message)
    } else {
      setRestaurants(data)
    }
    setLoading(false)
  }

  const filteredRestaurants = useMemo(() => {
    let result = [...restaurants]

    if (searchTerm.trim()) {
      const keyword = searchTerm.trim().toLowerCase()
      result = result.filter((r) => r.name.toLowerCase().includes(keyword))
    }

    if (statusFilter === 'open') {
      result = result.filter((r) => r.is_open)
    } else if (statusFilter === 'closed') {
      result = result.filter((r) => !r.is_open)
    }

    if (sortBy === 'name') {
      result.sort((a, b) => a.name.localeCompare(b.name, 'vi'))
    }

    return result
  }, [restaurants, searchTerm, statusFilter, sortBy])

  return (
    <CustomerLayout>
      <div className="max-w-5xl mx-auto px-4 py-6">
        <h2 className="text-2xl font-bold mb-4">Nhà hàng gần bạn</h2>

        <div className="flex flex-col sm:flex-row gap-3 mb-6">
          <input
            type="text"
            placeholder="Tìm nhà hàng theo tên..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="flex-1 border rounded px-4 py-2 focus:outline-none focus:ring-2 focus:ring-orange-400"
          />

          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="border rounded px-3 py-2 bg-white"
          >
            <option value="all">Tất cả</option>
            <option value="open">Đang mở cửa</option>
            <option value="closed">Đã đóng cửa</option>
          </select>

          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value)}
            className="border rounded px-3 py-2 bg-white"
          >
            <option value="newest">Mới nhất</option>
            <option value="name">Tên A-Z</option>
          </select>
        </div>

        {loading && <p className="text-gray-500">Đang tải danh sách nhà hàng...</p>}
        {error && <p className="text-red-500">{error}</p>}

        {!loading && filteredRestaurants.length === 0 && (
          <p className="text-gray-500 text-center py-8">
            {searchTerm
              ? `Không tìm thấy nhà hàng nào khớp với "${searchTerm}".`
              : 'Chưa có nhà hàng nào.'}
          </p>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredRestaurants.map((restaurant) => (
            <RestaurantCard key={restaurant.id} restaurant={restaurant} />
          ))}
        </div>
      </div>
    </CustomerLayout>
  )
}