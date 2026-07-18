import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'

export default function Register() {
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [role, setRole] = useState('customer')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const navigate = useNavigate()

  async function handleRegister(e) {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const res = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/register-user`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`
          },
          body: JSON.stringify({ email, password, fullName, role })
        }
      )
      const data = await res.json()

      if (data.error) {
        setError(data.error)
      } else {
        setSuccess(true)
      }
    } catch (err) {
      setError('Có lỗi xảy ra, thử lại sau')
    } finally {
      setLoading(false)
    }
  }

  if (success) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-50">
        <div className="bg-white p-8 rounded-lg shadow-md text-center max-w-sm">
          <h2 className="text-xl font-bold mb-2">Đăng ký thành công!</h2>
          <p className="text-gray-600 mb-4">Bạn có thể đăng nhập ngay bây giờ.</p>
          <button onClick={() => navigate('/login')} className="text-orange-500 font-medium">
            Về trang đăng nhập
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-50">
      <form onSubmit={handleRegister} className="bg-white p-8 rounded-lg shadow-md w-full max-w-sm">
        <h1 className="text-2xl font-bold mb-6 text-center">Đăng ký</h1>
        {error && <p className="text-red-500 text-sm mb-4">{error}</p>}

        <input type="text" placeholder="Họ và tên" value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          className="w-full border rounded px-3 py-2 mb-4" required />

        <input type="email" placeholder="Email" value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full border rounded px-3 py-2 mb-4" required />

        <input type="password" placeholder="Mật khẩu" value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full border rounded px-3 py-2 mb-4" minLength={6} required />

        <label className="block text-sm text-gray-600 mb-2">Bạn là:</label>
        <select value={role} onChange={(e) => setRole(e.target.value)}
          className="w-full border rounded px-3 py-2 mb-4">
          <option value="customer">Khách hàng</option>
          <option value="restaurant">Chủ nhà hàng</option>
        </select>

        <button type="submit" disabled={loading}
          className="w-full bg-orange-500 text-white py-2 rounded hover:bg-orange-600 disabled:opacity-50">
          {loading ? 'Đang xử lý...' : 'Đăng ký'}
        </button>

        <p className="text-sm text-center mt-4 text-gray-600">
          Đã có tài khoản? <Link to="/login" className="text-orange-500">Đăng nhập</Link>
        </p>
      </form>
    </div>
  )
}