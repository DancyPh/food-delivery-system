import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import FoodCard from '../../components/FoodCard'
import FoodDetailModal from '../../components/FoodDetailModal'
import CustomerLayout from '../../components/CustomerLayout'

export default function RestaurantDetail() {
  const { id } = useParams()
  const [restaurant, setRestaurant] = useState(null)
  const [categories, setCategories] = useState([])
  const [foods, setFoods] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [selectedFood, setSelectedFood] = useState(null)

  useEffect(() => {
    fetchData()
  }, [id])

  async function fetchData() {
    setLoading(true)
    setError('')

    const [restaurantRes, categoriesRes, foodsRes] = await Promise.all([
      supabase.from('restaurants').select('*').eq('id', id).single(),
      supabase.from('categories').select('*').eq('restaurant_id', id).order('created_at'),
      supabase.from('foods').select('*').eq('restaurant_id', id).order('created_at'),
    ])

    if (restaurantRes.error) {
      setError('Không tìm thấy nhà hàng')
      setLoading(false)
      return
    }

    setRestaurant(restaurantRes.data)
    setCategories(categoriesRes.data ?? [])
    setFoods(foodsRes.data ?? [])
    setLoading(false)
  }

  function handleAddToCart(food) {
    console.log('Thêm vào giỏ:', food)
  }

  function handleViewDetail(food) {
    setSelectedFood(food)
  }

  function closeModal() {
    setSelectedFood(null)
  }

  function foodsByCategory(categoryId) {
    return foods.filter((f) => f.category_id === categoryId)
  }

  const uncategorizedFoods = foods.filter((f) => !f.category_id)

  if (loading) {
    return (
        <CustomerLayout>
        <div className="p-8 text-center text-gray-500">Đang tải...</div>
        </CustomerLayout>
    )
    }

    if (error) {
        return (
            <CustomerLayout>
            <div className="p-8 text-center">
                <p className="text-red-500">{error}</p>
                <Link to="/customer" className="text-orange-500 hover:underline">
                Về trang chủ
                </Link>
            </div>
            </CustomerLayout>
        )
    }

  return (
    <CustomerLayout>
      <div className="bg-white shadow-sm">
        <div className="max-w-3xl mx-auto px-4 py-4">
          <Link to="/customer" className="text-sm text-orange-500 hover:underline">
            ← Về trang chủ
          </Link>
          <h1 className="text-2xl font-bold mt-2">{restaurant.name}</h1>
          <p className="text-gray-500">{restaurant.description}</p>
          <p className="text-sm text-gray-400 mt-1">
            {restaurant.is_open ? (
              <span className="text-green-600">● Đang mở cửa</span>
            ) : (
              <span className="text-red-500">● Đã đóng cửa</span>
            )}
          </p>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-8">
        {foods.length === 0 && (
          <p className="text-gray-500 text-center">Nhà hàng chưa có món ăn nào.</p>
        )}

        {categories.map((category) => {
          const items = foodsByCategory(category.id)
          if (items.length === 0) return null

          return (
            <div key={category.id}>
              <h2 className="text-lg font-semibold mb-3">{category.name}</h2>
              <div className="space-y-3">
                {items.map((food) => (
                  <FoodCard
                    key={food.id}
                    food={food}
                    onAddToCart={handleAddToCart}
                    onViewDetail={handleViewDetail}
                  />
                ))}
              </div>
            </div>
          )
        })}

        {uncategorizedFoods.length > 0 && (
          <div>
            <h2 className="text-lg font-semibold mb-3">Món khác</h2>
            <div className="space-y-3">
              {uncategorizedFoods.map((food) => (
                <FoodCard
                  key={food.id}
                  food={food}
                  onAddToCart={handleAddToCart}
                  onViewDetail={handleViewDetail}
                />
              ))}
            </div>
          </div>
        )}
      </div>

      <FoodDetailModal
        food={selectedFood}
        onClose={closeModal}
        onAddToCart={handleAddToCart}
      />
    </CustomerLayout>
  )
}