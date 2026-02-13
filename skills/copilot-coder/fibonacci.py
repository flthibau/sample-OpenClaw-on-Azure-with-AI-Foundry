from functools import lru_cache


@lru_cache(maxsize=None)
def fibonacci(n: int) -> int:
    """
    Calculate the nth Fibonacci number using memoization.
    
    The Fibonacci sequence is defined as:
    F(0) = 0, F(1) = 1, F(n) = F(n-1) + F(n-2) for n > 1
    
    Args:
        n: The position in the Fibonacci sequence (0-indexed)
        
    Returns:
        The nth Fibonacci number
        
    Raises:
        ValueError: If n is negative
        
    Examples:
        >>> fibonacci(0)
        0
        >>> fibonacci(1)
        1
        >>> fibonacci(10)
        55
    """
    if n < 0:
        raise ValueError("n must be a non-negative integer")
    
    if n <= 1:
        return n
    
    return fibonacci(n - 1) + fibonacci(n - 2)
