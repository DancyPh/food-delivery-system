import { Link } from 'react-router-dom'

export default function RestaurantCard({ restaurant }) {
  return (
    <Link
      to={`/customer/restaurant/${restaurant.id}`}
      className="block bg-white rounded-lg shadow hover:shadow-md transition overflow-hidden"
    >
      <div className="aspect-video bg-gray-100">
        {restaurant.image ? (
          <img
            src={restaurant.image}
            alt={restaurant.name}
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-gray-400">
            Chưa có ảnh
          </div>
        )}
      </div>
      <div className="p-4">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold text-lg truncate">{restaurant.name}</h3>
          {!restaurant.is_open && (
            <span className="text-xs bg-gray-200 text-gray-600 px-2 py-1 rounded">
              Đóng cửa
            </span>
          )}
        </div>
        <p className="text-gray-500 text-sm mt-1 line-clamp-2">
          {restaurant.description}
        </p>
      </div>
    </Link>
  )
}